import PDFKit
import PencilKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.fromink.app", category: "PDFCanvas")

// MARK: - Custom annotation key for identity round-trip

extension PDFAnnotationKey {
    /// Custom annotation key we stamp on every `PDFKit.PDFAnnotation` we
    /// create so the reconcile loop can identify "our" annotations by
    /// `PDFAnnotationSnapshot.id`. PDFKit preserves unknown keys in
    /// memory; whether they survive PDF export depends on the writer
    /// path (PDFView's `dataRepresentation()` keeps them). Embedded
    /// annotations imported from the source PDF do not carry this key,
    /// so the reconcile loop won't accidentally touch them.
    static let fromInkID = PDFAnnotationKey(rawValue: "FromInkID")
}

// MARK: - Reconcile

/// Diff-by-id reconcile of our `PDFAnnotationSnapshot` records against
/// PDFKit's `PDFView.annotations`. Adds, removes, and updates in-place
/// rather than tearing down + rebuilding the full set, so PDFView's
/// own scrolling/selection state doesn't reset on every state change.
///
/// Embedded annotations from the source PDF (those without the
/// `FromInkID` key) are left alone — only annotations we've authored
/// participate in the diff.
@MainActor
private func reconcileAnnotations(
    desired: [PDFAnnotationSnapshot],
    in pdfView: PDFView
) {
    guard let document = pdfView.document else { return }

    // Index desired snapshots by id.
    let desiredByID: [UUID: PDFAnnotationSnapshot] = Dictionary(
        uniqueKeysWithValues: desired.map { ($0.id, $0) }
    )

    // Walk every page and index "ours" by id.
    var existingByID: [UUID: PDFKit.PDFAnnotation] = [:]
    for pageIndex in 0..<document.pageCount {
        guard let page = document.page(at: pageIndex) else { continue }
        for annotation in page.annotations {
            guard let idString = annotation.value(forAnnotationKey: .fromInkID) as? String,
                  let id = UUID(uuidString: idString)
            else { continue }
            existingByID[id] = annotation
        }
    }

    // Remove vanished annotations.
    for (id, existing) in existingByID where desiredByID[id] == nil {
        existing.page?.removeAnnotation(existing)
    }

    // Add new annotations.
    for (id, snapshot) in desiredByID where existingByID[id] == nil {
        guard let page = document.page(at: snapshot.pageIndex) else { continue }
        if let pdfAnnotation = makePDFAnnotation(from: snapshot, page: page) {
            page.addAnnotation(pdfAnnotation)
        }
    }

    // Update path lands when edit-color / edit-bounds ships — today
    // an existing annotation never changes shape, so remove+add isn't
    // exercised on edits. New highlights flow through as adds; the
    // delete path strips via id match.
}

/// Builds a `PDFKit.PDFAnnotation` from one of our snapshots. Returns
/// nil for kinds the viewer doesn't render yet (freeText, line,
/// square, circle, polygon, raw ink) — those land in their own phases.
/// Highlights, underlines, and pencil drawings render today.
@MainActor
private func makePDFAnnotation(
    from snapshot: PDFAnnotationSnapshot,
    page: PDFPage
) -> PDFKit.PDFAnnotation? {
    let bounds = denormalize(snapshot.bounds, in: page)
    let color = UIColor(
        red: snapshot.color.r,
        green: snapshot.color.g,
        blue: snapshot.color.b,
        alpha: snapshot.color.a
    )

    let pdfAnnotation: PDFKit.PDFAnnotation?
    switch snapshot.kind {
    case .highlight:
        pdfAnnotation = PDFKit.PDFAnnotation(
            bounds: bounds, forType: .highlight, withProperties: nil
        )
    case .underline:
        pdfAnnotation = PDFKit.PDFAnnotation(
            bounds: bounds, forType: .underline, withProperties: nil
        )
    case .pencil:
        // Phase 5a read path: deserialize PKDrawing, convert strokes
        // to PDFKit-native `.ink` paths so the rendering is vector
        // and zoom-aware. The original PKDrawing bytes ride on the
        // snapshot — Phase 5b's edit path will re-hydrate a
        // PKCanvasView from them.
        guard let drawingData = snapshot.pencilDrawing else {
            log.warning("Pencil snapshot \(snapshot.id, privacy: .public) has no drawing bytes; skipping render")
            return nil
        }
        pdfAnnotation = makeInkFromPencilDrawing(
            data: drawingData,
            pageBounds: page.bounds(for: .cropBox)
        )
    case .freeText, .line, .square, .circle, .polygon, .ink:
        // Render paths land in their own phases; for v1 skip silently
        // so a stray record doesn't crash the viewer.
        return nil
    }

    guard let pdfAnnotation else { return nil }
    // Pencil renders the bezier strokes' own colors — overriding the
    // PDFAnnotation.color would re-tint every stroke uniformly and
    // erase the per-stroke color the user drew. Highlights and
    // underlines have no per-stroke color, so they take the
    // snapshot's color.
    if snapshot.kind != .pencil {
        pdfAnnotation.color = color
    }
    pdfAnnotation.setValue(snapshot.id.uuidString, forAnnotationKey: .fromInkID)
    return pdfAnnotation
}

/// Deserializes a `PKDrawing` from its `dataRepresentation()` bytes
/// and converts each stroke to a `UIBezierPath`, mounted on a PDFKit
/// `.ink` annotation. Vector output, zoom-aware in PDFView.
///
/// Returns nil if the bytes don't parse as a valid PKDrawing — logs
/// and skips so a single corrupt record doesn't crash the viewer.
@MainActor
private func makeInkFromPencilDrawing(
    data: Data,
    pageBounds: CGRect
) -> PDFKit.PDFAnnotation? {
    let drawing: PKDrawing
    do {
        drawing = try PKDrawing(data: data)
    } catch {
        log.warning("Failed to deserialize PKDrawing (\(data.count, privacy: .public) bytes): \(error.localizedDescription, privacy: .public)")
        return nil
    }

    // Drawing bounds in PencilKit's own coordinate space — same as
    // the page cropBox we use for our normalized snapshot bounds.
    let drawingBounds = drawing.bounds
    let annotationBounds = drawingBounds.intersection(pageBounds)
    guard !annotationBounds.isNull, !annotationBounds.isEmpty else { return nil }

    let ink = PDFKit.PDFAnnotation(
        bounds: annotationBounds,
        forType: .ink,
        withProperties: nil
    )

    let paths = bezierPaths(from: drawing)
    for path in paths {
        ink.add(path)
    }
    return ink
}

/// Converts a `PKDrawing`'s strokes into `UIBezierPath`s suitable for
/// `PDFAnnotation.add(_:)`. Each stroke samples its
/// `PKStrokePath.interpolatedPoints(by:)` at a small fixed distance
/// — fine enough to preserve pen curvature, coarse enough to keep
/// path count manageable for big drawings.
@MainActor
private func bezierPaths(from drawing: PKDrawing) -> [UIBezierPath] {
    drawing.strokes.map { stroke in
        let path = UIBezierPath()
        var first = true
        stroke.path.forEach { point in
            let location = point.location
            if first {
                path.move(to: location)
                first = false
            } else {
                path.addLine(to: location)
            }
        }
        path.lineWidth = 2
        return path
    }
}

/// Denormalizes the 0..1 snapshot bounds back into PDF page user-space.
/// Page bounds depend on the page's `cropBox` since that's what PDFView
/// renders.
@MainActor
private func denormalize(_ normalized: CGRect, in page: PDFPage) -> CGRect {
    let pageBounds = page.bounds(for: .cropBox)
    return CGRect(
        x: pageBounds.origin.x + normalized.origin.x * pageBounds.size.width,
        y: pageBounds.origin.y + normalized.origin.y * pageBounds.size.height,
        width: normalized.size.width * pageBounds.size.width,
        height: normalized.size.height * pageBounds.size.height
    )
}

// MARK: - Selection extraction

/// Splits a `PDFSelection` into one `HighlightLine` per visible line
/// using `PDFSelection.selectionsByLine()` so highlights wrap text
/// rather than painting one giant cross-line rectangle (Acrobat /
/// Books convention).
///
/// Bounds normalize against each line's page cropBox — same
/// coordinate space `PDFAnnotation.bounds` stores and the reconcile
/// loop's `denormalize` reverses.
@MainActor
private func extractHighlightLines(
    from selection: PDFSelection,
    in pdfView: PDFView
) -> [HighlightLine] {
    guard let document = pdfView.document else { return [] }

    let perLine = selection.selectionsByLine()
    var lines: [HighlightLine] = []
    lines.reserveCapacity(perLine.count)

    for lineSelection in perLine {
        // A line selection belongs to exactly one page; take the
        // first.
        guard let page = lineSelection.pages.first,
              let pageIndex = document.index(for: page) as Int?,
              let text = lineSelection.string,
              !text.isEmpty
        else { continue }

        let rawBounds = lineSelection.bounds(for: page)
        let normalized = normalize(rawBounds, in: page)

        lines.append(HighlightLine(
            pageIndex: pageIndex,
            bounds: normalized,
            extractedText: text
        ))
    }

    return lines
}

/// Inverse of `denormalize` — converts page-space bounds back to
/// 0..1 normalized.
@MainActor
private func normalize(_ rect: CGRect, in page: PDFPage) -> CGRect {
    let pageBounds = page.bounds(for: .cropBox)
    guard pageBounds.size.width > 0, pageBounds.size.height > 0 else {
        return .zero
    }
    return CGRect(
        x: (rect.origin.x - pageBounds.origin.x) / pageBounds.size.width,
        y: (rect.origin.y - pageBounds.origin.y) / pageBounds.size.height,
        width: rect.size.width / pageBounds.size.width,
        height: rect.size.height / pageBounds.size.height
    )
}

// MARK: - PDFCanvas

/// SwiftUI host for an already-parsed `PDFKit.PDFDocument`. Thin
/// `UIViewRepresentable` wrapper around `PDFKit.PDFView` — assumes the
/// document is ready and just mounts it.
///
/// Parsing happens upstream in `PDFContent` so the heavy
/// `PDFKit.PDFDocument(data:)` walk doesn't block the MainActor. See
/// the comment on `PDFContent` for the parse pipeline.
///
/// Renders annotations via the reconcile loop on every SwiftUI
/// re-render. Selection-to-highlight extraction runs when the parent
/// publishes a new `HighlightTrigger` — the coordinator dedupes via
/// trigger id so a stable trigger value across re-renders doesn't
/// re-fire.
struct PDFCanvas: UIViewRepresentable {
    let document: PDFKit.PDFDocument
    let annotations: [PDFAnnotationSnapshot]
    @Binding var currentPage: Int
    /// Fired when the user picks **Highlight** from the system
    /// text-selection edit menu. The coordinator extracts the
    /// per-line highlights from PDFView's current selection and calls
    /// this closure; the wiring view dispatches
    /// `.createHighlightFromSelection(lines)`.
    let onHighlightExtracted: ([HighlightLine]) -> Void
    /// Fired when the user taps an existing annotation and chooses
    /// "Remove" from the edit menu. Parent dispatches to
    /// `PDFFeature.deleteAnnotation(id)`.
    let onAnnotationDeleteRequested: (UUID) -> Void
    /// Whether the parent's search affordance is open. When it flips
    /// from `true` to `false`, the coordinator drops its cached
    /// `[PDFSelection]` and any search-owned current selection — no
    /// stale match-highlight survives a close-reopen.
    let isSearchActive: Bool
    /// Latest search request. When a new id arrives, the coordinator
    /// runs `findString` on the document, caches the selections, and
    /// jumps to the first match. Stable across renders means "no new
    /// request".
    let searchTrigger: SearchTrigger?
    /// Step-the-cursor request — next or previous match. Coordinator
    /// advances its internal index, jumps via `PDFView.go(to:)`, and
    /// reports the new 1-based index.
    let gotoMatchTrigger: GotoMatchTrigger?
    /// Fired after `findString` completes. `count` is total matches;
    /// `currentIndex` is 1-based (1 if any matches; 0 otherwise).
    let onSearchResults: (_ count: Int, _ currentIndex: Int) -> Void
    /// Fired after a step advances the cursor. New 1-based index.
    let onCurrentMatchChanged: (Int) -> Void
    /// Whether drawing mode is active. When `true`, the coordinator
    /// mounts a `PKCanvasView` over the visible page and locks the
    /// PDFView's scroll/zoom gestures. When it flips back to `false`,
    /// the canvas is torn down.
    let isDrawingActive: Bool
    /// Current drawing tool. The coordinator translates this to a
    /// `PKTool` on the mounted canvas. Changes mid-drawing don't
    /// disturb existing strokes.
    let drawingTool: PDFDrawingTool
    /// Current ink color for inking tools (pen, pencil, marker).
    /// The eraser and lasso ignore it. Mutates the mounted canvas's
    /// tool in place when changed.
    let drawingInkColor: PDFAnnotationColor
    /// Current stroke width preset for inking tools. Eraser and
    /// lasso ignore it.
    let drawingInkWidth: PDFDrawingInkWidth
    /// One-shot — when a new id arrives the coordinator serializes
    /// the canvas's drawing and fires `onDrawingCommitted`.
    let drawingCommitTrigger: DrawingCommitTrigger?
    /// One-shot — when a new id arrives the coordinator calls
    /// `undoManager.undo()` or `.redo()` on the mounted canvas.
    let drawingUndoTrigger: DrawingUndoTrigger?
    /// Fired after commit-trigger consumption with the PKDrawing
    /// bytes + normalized bounds + page index.
    let onDrawingCommitted: (_ bytes: Data, _ bounds: CGRect, _ pageIndex: Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = FromInkPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(DesignSystem.standard.colors.paper)
        view.document = document
        view.fromInkCoordinator = context.coordinator
        // Register the **Highlight** edit-menu item on first mount.
        // Process-global and idempotent.
        FromInkPDFView.registerMenuItemIfNeeded()

        // Tell the coordinator about the host view + the latest
        // callbacks. `attach` updates the closure refs on every render
        // through `refreshCallbacks` — the edit-menu interaction
        // install only happens once.
        context.coordinator.attach(pdfView: view)
        context.coordinator.refreshCallbacks(
            onDelete: onAnnotationDeleteRequested,
            onHighlight: onHighlightExtracted,
            onSearchResults: onSearchResults,
            onCurrentMatchChanged: onCurrentMatchChanged,
            onDrawingCommitted: onDrawingCommitted
        )

        // First-time annotation install — updateUIView also runs the
        // reconcile, but on initial render the annotations array may
        // already be populated from state.
        reconcileAnnotations(desired: annotations, in: view)

        // PDFView posts `PDFViewPageChanged` on visible-page changes;
        // the coordinator forwards them via the binding so the parent
        // reducer can scope annotation rendering by page.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: view
        )

        // PDFView posts `PDFViewAnnotationHit` when an annotation is
        // tapped. The coordinator filters for "ours" (FromInkID-stamped)
        // and presents the edit menu.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.annotationDidHit(_:)),
            name: .PDFViewAnnotationHit,
            object: view
        )

        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Refresh the callback closures — `makeUIView` only fires
        // once but `PDFCanvas` is value-typed and re-created on every
        // SwiftUI re-render. Without this refresh, a delete tap would
        // call the closure captured at first mount (and indirectly its
        // store reference); promoting closures to `var` on the
        // coordinator means a future refactor that captures scalars
        // doesn't silently break.
        context.coordinator.refreshCallbacks(
            onDelete: onAnnotationDeleteRequested,
            onHighlight: onHighlightExtracted,
            onSearchResults: onSearchResults,
            onCurrentMatchChanged: onCurrentMatchChanged,
            onDrawingCommitted: onDrawingCommitted
        )

        // Sync search-active edges. The coordinator drops its cached
        // results on the active → inactive transition so a stale
        // selection doesn't survive a close-reopen.
        context.coordinator.setSearchActive(isSearchActive)

        // Sync drawing-active edges. On open: mount PKCanvasView over
        // the visible page, lock PDFView gestures. On close: tear
        // down. The coordinator handles the actual mount lifecycle so
        // the SwiftUI struct stays declarative.
        context.coordinator.setDrawingActive(
            isDrawingActive,
            tool: drawingTool,
            color: drawingInkColor,
            width: drawingInkWidth,
            in: uiView
        )

        // Consume a fresh drawing-commit trigger.
        if let trigger = drawingCommitTrigger,
           trigger.id != context.coordinator.lastConsumedCommitTriggerID {
            context.coordinator.lastConsumedCommitTriggerID = trigger.id
            context.coordinator.commitDrawing(in: uiView)
        }

        // Consume a fresh undo / redo trigger.
        if let trigger = drawingUndoTrigger,
           trigger.id != context.coordinator.lastConsumedUndoTriggerID {
            context.coordinator.lastConsumedUndoTriggerID = trigger.id
            context.coordinator.applyUndo(direction: trigger.direction)
        }

        // Reconcile annotations on every SwiftUI re-render driven by
        // state changes (annotations loaded, new highlight created).
        // Diff-by-id keeps the common case cheap.
        reconcileAnnotations(desired: annotations, in: uiView)

        // Highlight extraction is driven by the system text-selection
        // edit menu (FromInkPDFView + UIMenuController.menuItems),
        // not a SwiftUI trigger — see the FromInkPDFView doc comment.
        // Nothing to consume here.

        // Consume a fresh search trigger — runs `findString` off
        // MainActor.
        if let trigger = searchTrigger,
           trigger.id != context.coordinator.lastConsumedSearchTriggerID {
            context.coordinator.lastConsumedSearchTriggerID = trigger.id
            context.coordinator.runSearch(query: trigger.query, in: uiView)
        }

        // Consume a fresh goto-match trigger.
        if let trigger = gotoMatchTrigger,
           trigger.id != context.coordinator.lastConsumedGotoTriggerID {
            context.coordinator.lastConsumedGotoTriggerID = trigger.id
            context.coordinator.step(direction: trigger.direction, in: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    @MainActor
    final class Coordinator: NSObject, UIEditMenuInteractionDelegate {
        let currentPage: Binding<Int>
        var lastConsumedSearchTriggerID: UUID?
        var lastConsumedGotoTriggerID: UUID?
        var lastConsumedCommitTriggerID: UUID?
        var lastConsumedUndoTriggerID: UUID?

        /// Weak reference back to the host PDFView so the edit-menu
        /// interaction can convert page-space tap points to view-space
        /// coordinates. PDFCanvas is value-typed and re-created on
        /// every SwiftUI re-render — the coordinator outlives the
        /// struct, so we cache the view here instead of capturing it.
        private weak var pdfView: PDFView?

        /// Edit-menu interaction installed on the PDFView. iOS 16+
        /// affordance for contextual menus on UIKit content; matches
        /// the system text-selection menu treatment used by Books and
        /// Mail. Created lazily on first attach.
        private var editMenuInteraction: UIEditMenuInteraction?

        // MARK: - Callbacks (refreshed every render)

        /// All three callbacks are `var` and refreshed in
        /// `updateUIView` via `refreshCallbacks` so a future caller
        /// that captures scalar state from the store (not the store
        /// itself) doesn't end up calling a closure pinned to the
        /// first render's value. `var` over `let` is the architectural
        /// guarantee here.
        private var onDelete: ((UUID) -> Void)?
        private var onHighlight: (([HighlightLine]) -> Void)?
        private var onSearchResults: ((Int, Int) -> Void)?
        private var onCurrentMatchChanged: ((Int) -> Void)?
        private var onDrawingCommitted: ((Data, CGRect, Int) -> Void)?

        // MARK: - Drawing mode

        /// The mounted `PKCanvasView` while drawing mode is active.
        /// `nil` when inactive — `setDrawingActive(true, ...)` creates
        /// and mounts; `setDrawingActive(false, ...)` removes.
        private var drawingCanvas: PKCanvasView?
        /// The PDF page the drawing canvas is anchored to. Captured
        /// at mount time so the commit path can normalize the drawing
        /// bounds against the right page's cropBox even if the user
        /// somehow scrolled to a new page mid-draw (shouldn't happen
        /// with the gesture lock, but the captured value is defensive).
        private var drawingPage: PDFPage?
        private var drawingPageIndex: Int = 0
        /// Saved PDFView gesture state so `setDrawingActive(false, ...)`
        /// can restore the pre-drawing-mode interaction model.
        private var savedPDFViewInteractionEnabled: Bool = true

        // MARK: - Search

        /// Search results from the last `findString` run. Coordinator
        /// owns these since `PDFSelection` is a non-Sendable reference
        /// type that can't ride through TCA actions or State.
        private var searchSelections: [PDFSelection] = []
        /// 0-based index into `searchSelections` for the currently
        /// anchored match. -1 when there are no results.
        private var currentMatchIndex: Int = -1
        /// `true` when the PDFView's current selection was set by the
        /// search machinery (via `setCurrentSelection`). Lets the
        /// no-match cleanup path clear search-owned selections
        /// without stomping a user-made text selection.
        private var selectionOwnedBySearch: Bool = false

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        deinit {
            // Defensive — selector-style observers are auto-removed on
            // dealloc since iOS 9, but the explicit cleanup makes the
            // intent obvious to readers.
            NotificationCenter.default.removeObserver(self)
        }

        /// One-time install — caches the host view and adds the
        /// `UIEditMenuInteraction`. Callable repeatedly: subsequent
        /// calls re-point the weak `pdfView` (idempotent) but skip
        /// re-installing the interaction.
        func attach(pdfView: PDFView) {
            self.pdfView = pdfView

            if editMenuInteraction == nil {
                let interaction = UIEditMenuInteraction(delegate: self)
                pdfView.addInteraction(interaction)
                editMenuInteraction = interaction
            }
        }

        /// Refreshes the per-render callback closures. Called from
        /// both `makeUIView` (first render) and `updateUIView` (every
        /// subsequent render) so a stale closure can never persist
        /// past one frame.
        func refreshCallbacks(
            onDelete: @escaping (UUID) -> Void,
            onHighlight: @escaping ([HighlightLine]) -> Void,
            onSearchResults: @escaping (Int, Int) -> Void,
            onCurrentMatchChanged: @escaping (Int) -> Void,
            onDrawingCommitted: @escaping (Data, CGRect, Int) -> Void
        ) {
            self.onDelete = onDelete
            self.onHighlight = onHighlight
            self.onSearchResults = onSearchResults
            self.onCurrentMatchChanged = onCurrentMatchChanged
            self.onDrawingCommitted = onDrawingCommitted
        }

        /// Called from `FromInkPDFView.highlightSelection(_:)` when
        /// the user picks **Highlight** from the system text-selection
        /// edit menu. Extracts per-line highlights from the current
        /// selection and dispatches via the refreshed callback. Clears
        /// the selection on success so the rendered highlight isn't
        /// fighting with the lingering selection overlay.
        func handleHighlightMenuItem(in pdfView: PDFView) {
            guard let selection = pdfView.currentSelection else { return }
            let lines = extractHighlightLines(from: selection, in: pdfView)
            guard !lines.isEmpty else { return }
            onHighlight?(lines)
            pdfView.clearSelection()
        }

        /// Resets the search machinery. Called from `runSearch` on
        /// query-with-no-matches and via `setSearchActive(false)` so
        /// the reducer's close-search path can wipe the coordinator's
        /// cached `[PDFSelection]`.
        func clearSearch() {
            searchSelections = []
            currentMatchIndex = -1
            if selectionOwnedBySearch {
                pdfView?.clearSelection()
                selectionOwnedBySearch = false
            }
        }

        /// Tracks whether the parent's search affordance is open.
        /// Calls `clearSearch` on the open → closed edge so closing
        /// the search bar tears down the result list and any
        /// search-owned current selection. Idempotent across renders.
        private var searchActive: Bool = false
        func setSearchActive(_ active: Bool) {
            let wasActive = searchActive
            searchActive = active
            if wasActive, !active {
                clearSearch()
                lastConsumedSearchTriggerID = nil
                lastConsumedGotoTriggerID = nil
            }
        }

        @objc func pageDidChange(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let index = view.document?.index(for: page)
            else { return }
            currentPage.wrappedValue = index
        }

        /// Posted by PDFView when an annotation receives a tap.
        /// Filters for annotations we authored (stamped with
        /// `FromInkID`); embedded annotations from the source PDF are
        /// ignored so user "Remove" can't touch them.
        ///
        /// The tapped annotation's UUID rides on the
        /// `UIEditMenuConfiguration.identifier` rather than via
        /// instance state — that way two near-simultaneous hits can't
        /// race against a shared `pendingAnnotationID`.
        @objc func annotationDidHit(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFKit.PDFAnnotation,
                  let idString = annotation.value(forAnnotationKey: .fromInkID) as? String,
                  let id = UUID(uuidString: idString),
                  let page = annotation.page
            else { return }

            // Convert the annotation's page-space bounds to view-space
            // so the menu can anchor at the annotation, not at a stale
            // tap location (PDFViewAnnotationHit doesn't expose the
            // raw touch point).
            let anchorInPage = CGPoint(
                x: annotation.bounds.midX,
                y: annotation.bounds.midY
            )
            let anchorInView = view.convert(anchorInPage, from: page)

            let config = UIEditMenuConfiguration(
                identifier: id.uuidString as NSString,
                sourcePoint: anchorInView
            )
            editMenuInteraction?.presentEditMenu(with: config)
        }

        // MARK: - UIEditMenuInteractionDelegate

        nonisolated func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            MainActor.assumeIsolated {
                // Identifier was stamped in `annotationDidHit`. Reading
                // here instead of instance state means two near-
                // simultaneous hits each carry their own id through
                // their own configuration.
                guard let idString = configuration.identifier as? String,
                      let id = UUID(uuidString: idString)
                else { return nil }

                let remove = UIAction(
                    title: AppStrings.Library.annotationRemoveAction,
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.onDelete?(id)
                }
                // Suggested actions cover copy/lookup/share — keep them
                // so the menu still feels like the system one; append
                // Remove at the end so destructive lives last per HIG.
                return UIMenu(children: suggestedActions + [remove])
            }
        }

        // MARK: - Search

        /// Runs `findString` against the current document and jumps the
        /// PDFView to the first match. The find runs on a detached task
        /// so a large-document search doesn't freeze the MainActor;
        /// `PDFDocument.findString` is documented thread-safe. The
        /// jump + `setCurrentSelection` hops back to MainActor.
        ///
        /// Search is case-insensitive AND diacritic-insensitive so
        /// "cafe" matches "café" — what users expect from a system
        /// reader.
        func runSearch(query: String, in pdfView: PDFView) {
            guard let document = pdfView.document else {
                clearSearch()
                onSearchResults?(0, 0)
                return
            }

            Task { [weak self, weak pdfView] in
                let matches = await Task.detached(priority: .userInitiated) {
                    document.findString(
                        query,
                        withOptions: [.caseInsensitive, .diacriticInsensitive]
                    )
                }.value

                guard let self, let pdfView else { return }
                self.applySearchResults(matches, in: pdfView)
            }
        }

        /// MainActor follow-up after the detached find. Reads-and-
        /// writes the coordinator's per-render search state. Split
        /// from `runSearch` so the off-actor task captures the minimum
        /// needed.
        private func applySearchResults(
            _ matches: [PDFSelection],
            in pdfView: PDFView
        ) {
            searchSelections = matches

            if let first = matches.first {
                currentMatchIndex = 0
                pdfView.go(to: first)
                pdfView.setCurrentSelection(first, animate: false)
                selectionOwnedBySearch = true
                onSearchResults?(matches.count, 1)
            } else {
                currentMatchIndex = -1
                // Only clear if we own the selection — a user mid-
                // text-select shouldn't lose their selection because
                // the search bar happens to be open with a non-
                // matching query.
                if selectionOwnedBySearch {
                    pdfView.clearSelection()
                    selectionOwnedBySearch = false
                }
                onSearchResults?(0, 0)
            }
        }

        /// Advances the cursor by one match in the given direction,
        /// cycling at the ends. No-op if there are no results — the
        /// reducer also guards but the canvas should be safe alone.
        func step(direction: GotoMatchTrigger.Direction, in pdfView: PDFView) {
            guard !searchSelections.isEmpty else { return }

            switch direction {
            case .next:
                currentMatchIndex = (currentMatchIndex + 1) % searchSelections.count
            case .previous:
                currentMatchIndex = (currentMatchIndex - 1 + searchSelections.count) % searchSelections.count
            }

            let selection = searchSelections[currentMatchIndex]
            pdfView.go(to: selection)
            pdfView.setCurrentSelection(selection, animate: false)
            selectionOwnedBySearch = true
            onCurrentMatchChanged?(currentMatchIndex + 1)
        }

        // MARK: - Drawing mode

        /// Tracks drawing-active edges. On false → true: mounts a
        /// `PKCanvasView` over the currently visible page and locks
        /// the PDFView's gestures so the user can't scroll/zoom
        /// mid-draw. On true → false (without commit): tears the
        /// canvas down. Tool, color, and width changes while active
        /// mutate the mounted canvas's `tool` in place — no remount.
        private var drawingActive: Bool = false
        func setDrawingActive(
            _ active: Bool,
            tool: PDFDrawingTool,
            color: PDFAnnotationColor,
            width: PDFDrawingInkWidth,
            in pdfView: PDFView
        ) {
            if active, !drawingActive {
                mountDrawingCanvas(tool: tool, color: color, width: width, in: pdfView)
            } else if !active, drawingActive {
                teardownDrawingCanvas(in: pdfView)
            } else if active, let canvas = drawingCanvas {
                // Tool / color / width changed mid-draw — update in
                // place.
                canvas.tool = pkTool(for: tool, color: color, width: width)
            }
            drawingActive = active
        }

        private func mountDrawingCanvas(
            tool: PDFDrawingTool,
            color: PDFAnnotationColor,
            width: PDFDrawingInkWidth,
            in pdfView: PDFView
        ) {
            guard let page = pdfView.currentPage,
                  let document = pdfView.document
            else { return }

            // Page bounds in PDF user-space — what `PKCanvasView`
            // strokes will live in once we set the matching frame.
            let pageBounds = page.bounds(for: .cropBox)
            // Convert page-space rect into PDFView-local view-space
            // for the actual subview frame.
            let topLeftInView = pdfView.convert(
                CGPoint(x: pageBounds.minX, y: pageBounds.maxY),
                from: page
            )
            let bottomRightInView = pdfView.convert(
                CGPoint(x: pageBounds.maxX, y: pageBounds.minY),
                from: page
            )
            let frameInView = CGRect(
                x: topLeftInView.x,
                y: topLeftInView.y,
                width: bottomRightInView.x - topLeftInView.x,
                height: bottomRightInView.y - topLeftInView.y
            )

            let canvas = PKCanvasView(frame: frameInView)
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = .pencilOnly
            canvas.tool = pkTool(for: tool, color: color, width: width)
            // PKCanvasView is itself a scroll view — disable its own
            // pan/zoom so only the strokes are captured.
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            canvas.isScrollEnabled = false

            pdfView.addSubview(canvas)

            drawingCanvas = canvas
            drawingPage = page
            drawingPageIndex = document.index(for: page)

            // Lock PDFView interaction so finger scroll can't navigate
            // mid-draw. Pencil still reaches the overlay since
            // PKCanvasView is the topmost view.
            savedPDFViewInteractionEnabled = pdfView.isUserInteractionEnabled
            pdfView.isUserInteractionEnabled = true   // keep gestures alive for the overlay
            pdfView.documentView?.isUserInteractionEnabled = false
        }

        private func teardownDrawingCanvas(in pdfView: PDFView) {
            drawingCanvas?.removeFromSuperview()
            drawingCanvas = nil
            drawingPage = nil
            drawingPageIndex = 0
            pdfView.documentView?.isUserInteractionEnabled = savedPDFViewInteractionEnabled
        }

        /// Triggered by `drawingCommitTrigger`. Serializes the
        /// mounted canvas's drawing, computes normalized bounds
        /// against the captured page, and reports the bytes via
        /// `onDrawingCommitted`. Empty drawings still report (with
        /// empty bytes) so the reducer can exit drawing mode
        /// uniformly.
        func commitDrawing(in pdfView: PDFView) {
            guard let canvas = drawingCanvas,
                  let page = drawingPage
            else {
                // Trigger arrived without a mounted canvas — defensive
                // exit. The reducer's guard on isDrawingActive should
                // prevent this, but report empty bytes so the
                // reducer's `.drawingCommitted` path can still exit.
                onDrawingCommitted?(Data(), .zero, drawingPageIndex)
                return
            }

            let drawing = canvas.drawing
            let pageIndex = drawingPageIndex

            if drawing.strokes.isEmpty {
                onDrawingCommitted?(Data(), .zero, pageIndex)
                teardownDrawingCanvas(in: pdfView)
                return
            }

            // PKCanvasView strokes live in PKCanvasView-local
            // coordinate space. The canvas's frame matches the page's
            // view-space bounds — so the drawing's bounds are already
            // in page-local space, modulo a translation by the canvas
            // origin. Use the canvas frame to recover that offset.
            //
            // For the normalized bounds: pull them against the page's
            // cropBox so render-time denormalize lines up.
            let drawingBoundsInCanvas = drawing.bounds
            let pageBounds = page.bounds(for: .cropBox)
            let normalized = normalize(drawingBoundsInCanvas, in: page)

            let bytes = drawing.dataRepresentation()
            log.info("Committed pencil drawing on page \(pageIndex, privacy: .public): \(bytes.count, privacy: .public) bytes, bounds \(String(describing: drawingBoundsInCanvas), privacy: .public) within page \(String(describing: pageBounds), privacy: .public)")

            onDrawingCommitted?(bytes, normalized, pageIndex)
            teardownDrawingCanvas(in: pdfView)
        }

        /// Maps our `(PDFDrawingTool, color, width)` triple to a
        /// PencilKit `PKTool`. The marker translucently applies its
        /// color (~40% alpha) and scales the width up so highlights
        /// read like a highlighter; pen and pencil use the color
        /// opaquely at the requested width. The eraser and lasso
        /// ignore color and width entirely.
        private func pkTool(
            for tool: PDFDrawingTool,
            color: PDFAnnotationColor,
            width: PDFDrawingInkWidth
        ) -> PKTool {
            let uiColor = UIColor(
                red: color.r, green: color.g, blue: color.b, alpha: color.a
            )
            let inkPoints = width.inkPoints
            switch tool {
            case .pen:
                return PKInkingTool(.pen, color: uiColor, width: inkPoints)
            case .pencil:
                return PKInkingTool(.pencil, color: uiColor, width: inkPoints)
            case .marker:
                // Marker is the highlighter — translucent, scaled up
                // to ~7× the ink width so highlights cover a line.
                let translucent = uiColor.withAlphaComponent(0.4)
                return PKInkingTool(.marker, color: translucent, width: inkPoints * 7)
            case .eraser:
                return PKEraserTool(.bitmap)
            case .lasso:
                return PKLassoTool()
            }
        }

        /// Triggered by `drawingUndoTrigger`. Calls the matching
        /// `undoManager` method on the mounted canvas. No-op if
        /// nothing's queued or the canvas isn't mounted — the always-
        /// tappable buttons in the toolbar are intentional; we don't
        /// dim them in 5c (state-tracking adds complexity better
        /// solved in 5d alongside the width picker).
        func applyUndo(direction: DrawingUndoTrigger.Direction) {
            guard let undoManager = drawingCanvas?.undoManager else { return }
            switch direction {
            case .undo:
                if undoManager.canUndo { undoManager.undo() }
            case .redo:
                if undoManager.canRedo { undoManager.redo() }
            }
        }
    }
}

// MARK: - PDFContent

/// SwiftUI wrapper that turns raw PDF bytes into a rendered viewer.
/// Owns the off-actor parse pipeline:
///
/// 1. `.task(id: data)` fires on first appearance.
/// 2. `Task.detached(priority: .userInitiated)` runs
///    `PDFKit.PDFDocument(data:)` — the heavy parse that walks the
///    whole document tree. Synchronous in PDFKit but isolated off
///    MainActor here, so the viewer stays responsive (spinner +
///    dismiss chrome remain interactive).
/// 3. On completion, the parsed document lands in `@State` and the
///    view swaps to `PDFCanvas`. Failures surface as the standard
///    viewer-load-failed message.
///
/// `PDFKit.PDFDocument` is a class reference, non-Sendable, and can't
/// be carried through TCA `Action` types or `State`. This local
/// SwiftUI ownership is the right boundary: the imperative UIKit
/// object lives entirely on the MainActor in the view layer; the
/// reducer hands raw `Data` and forgets.
struct PDFContent: View {
    let data: Data
    let annotations: [PDFAnnotationSnapshot]
    @Binding var currentPage: Int
    /// Fired when the user taps the highlight button while text is
    /// selected. Each call carries one `HighlightLine` per text line
    /// the selection spans; the parent dispatches them to
    /// `PDFFeature.createHighlightFromSelection`.
    let onHighlightExtracted: ([HighlightLine]) -> Void
    /// Fired when the user taps an existing annotation and selects
    /// "Remove" from the edit menu. Parent dispatches to
    /// `PDFFeature.deleteAnnotation(id)`.
    let onAnnotationDeleteRequested: (UUID) -> Void
    /// Whether the parent's search affordance is open. Closing the
    /// affordance signals the canvas to clear its cached results.
    let isSearchActive: Bool
    /// Latest search request from the parent reducer. `nil` between
    /// submissions.
    let searchTrigger: SearchTrigger?
    /// Latest step-cursor request from the parent reducer.
    let gotoMatchTrigger: GotoMatchTrigger?
    /// Fired after the canvas runs `findString`. Parent stores
    /// (count, currentIndex) in state.
    let onSearchResults: (_ count: Int, _ currentIndex: Int) -> Void
    /// Fired after the canvas advances its match cursor.
    let onCurrentMatchChanged: (Int) -> Void
    /// Drawing-mode pass-throughs from the wiring view.
    let isDrawingActive: Bool
    let drawingTool: PDFDrawingTool
    let drawingInkColor: PDFAnnotationColor
    let drawingInkWidth: PDFDrawingInkWidth
    let drawingCommitTrigger: DrawingCommitTrigger?
    let drawingUndoTrigger: DrawingUndoTrigger?
    let onDrawingCommitted: (_ bytes: Data, _ bounds: CGRect, _ pageIndex: Int) -> Void

    @State private var parseResult: ParseResult = .parsing

    private enum ParseResult {
        case parsing
        case parsed(PDFKit.PDFDocument)
        case failed
    }

    var body: some View {
        Group {
            switch parseResult {
            case .parsing:
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .parsed(let document):
                parsedBody(document: document)

            case .failed:
                VStack(spacing: DesignSystem.standard.spacing.base) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(DesignSystem.standard.colors.flagRed)
                    Text(AppStrings.Library.pdfViewerLoadFailedMessage)
                        .font(.system(size: 15))
                        .foregroundStyle(DesignSystem.standard.colors.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.standard.spacing.lg)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: data) {
            // Off-MainActor parse. `Task.detached` ensures the parse
            // runs on a global cooperative queue, not our captured
            // MainActor. `Data` is Sendable so capture is clean.
            let captured = data
            let document = await Task.detached(priority: .userInitiated) {
                PDFKit.PDFDocument(data: captured)
            }.value

            // Back on MainActor after the await — safe to mutate
            // @State directly.
            if let document {
                parseResult = .parsed(document)
            } else {
                parseResult = .failed
            }
        }
    }

    /// Extracted from `body` to relieve the SwiftUI type-checker —
    /// the inline `switch` arm with the full `PDFCanvas` argument
    /// list was sitting right at the type-inference ceiling.
    private func parsedBody(document: PDFKit.PDFDocument) -> some View {
        PDFCanvas(
            document: document,
            annotations: annotations,
            currentPage: $currentPage,
            onHighlightExtracted: onHighlightExtracted,
            onAnnotationDeleteRequested: onAnnotationDeleteRequested,
            isSearchActive: isSearchActive,
            searchTrigger: searchTrigger,
            gotoMatchTrigger: gotoMatchTrigger,
            onSearchResults: onSearchResults,
            onCurrentMatchChanged: onCurrentMatchChanged,
            isDrawingActive: isDrawingActive,
            drawingTool: drawingTool,
            drawingInkColor: drawingInkColor,
            drawingInkWidth: drawingInkWidth,
            drawingCommitTrigger: drawingCommitTrigger,
            drawingUndoTrigger: drawingUndoTrigger,
            onDrawingCommitted: onDrawingCommitted
        )
    }
}
