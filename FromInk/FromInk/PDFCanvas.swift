import PDFKit
import SwiftUI

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

    // Phase 4a is create-only — annotations are immutable for v1.
    // Phase 4b adds the update path here when edit-color / edit-bounds
    // ships.
}

/// Builds a `PDFKit.PDFAnnotation` from one of our snapshots. Returns
/// nil for kinds the v1 viewer doesn't render yet (ink, pencil,
/// freeText, shape) — those land in later phases. Highlights and
/// underlines render today.
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
    case .freeText, .line, .square, .circle, .polygon, .ink, .pencil:
        // Render paths land in their own phases; for v1 skip silently
        // so a stray record doesn't crash the viewer.
        return nil
    }

    guard let pdfAnnotation else { return nil }
    pdfAnnotation.color = color
    pdfAnnotation.setValue(snapshot.id.uuidString, forAnnotationKey: .fromInkID)
    return pdfAnnotation
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

// MARK: - HighlightTrigger

/// One-shot signal asking `PDFCanvas` to convert the current
/// `PDFView.currentSelection` into `HighlightLine`s and fire
/// `onHighlightExtracted`. The wrapping UUID makes each tap a fresh
/// trigger so SwiftUI re-renders propagate; the coordinator compares
/// against the last consumed id to dedupe.
///
/// Mirrors the `scrollTo: Binding<CGPoint?>` pattern used by
/// `CanvasView` for the handwriting canvas — the SwiftUI side
/// publishes a request, the UIKit coordinator consumes it imperatively.
struct HighlightTrigger: Equatable {
    let id: UUID
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
              let pageIndex = document.index(for: page) as Int?
        else { continue }

        let rawBounds = lineSelection.bounds(for: page)
        let normalized = normalize(rawBounds, in: page)
        let text = lineSelection.string ?? ""

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
    let highlightTrigger: HighlightTrigger?
    let onHighlightExtracted: ([HighlightLine]) -> Void
    /// Fired when the user taps an existing annotation and chooses
    /// "Remove" from the edit menu. Parent dispatches to
    /// `PDFFeature.deleteAnnotation(id)`.
    let onAnnotationDeleteRequested: (UUID) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Color.canvas)
        view.document = document

        // Tell the coordinator about the host view so the edit-menu
        // interaction has a UIView to attach to and can present the
        // menu anchored at the tap location.
        context.coordinator.attach(pdfView: view, onDelete: onAnnotationDeleteRequested)

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
        // Reconcile annotations on every SwiftUI re-render driven by
        // state changes (annotations loaded, new highlight created).
        // Diff-by-id keeps the common case cheap.
        reconcileAnnotations(desired: annotations, in: uiView)

        // Consume a fresh highlight trigger. Coordinator tracks the
        // last consumed id so a stable trigger across unrelated
        // re-renders doesn't re-extract.
        if let trigger = highlightTrigger,
           trigger.id != context.coordinator.lastConsumedHighlightTriggerID {
            context.coordinator.lastConsumedHighlightTriggerID = trigger.id
            processHighlight(in: uiView)
        }
    }

    /// Reads `PDFView.currentSelection`, splits it per line,
    /// normalizes bounds, and hands the result to the parent. Clears
    /// the selection on success so the user sees the highlight render
    /// without the selection overlay competing visually. Silent no-op
    /// if no text is selected — the trigger button is always tappable
    /// and the user learns "select first" by trying.
    @MainActor
    private func processHighlight(in pdfView: PDFView) {
        guard let selection = pdfView.currentSelection else { return }
        let lines = extractHighlightLines(from: selection, in: pdfView)
        guard !lines.isEmpty else { return }
        onHighlightExtracted(lines)
        pdfView.clearSelection()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    @MainActor
    final class Coordinator: NSObject, UIEditMenuInteractionDelegate {
        let currentPage: Binding<Int>
        var lastConsumedHighlightTriggerID: UUID?

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

        /// Callback to surface the user's "Remove" choice back to TCA.
        /// Re-attached on every `makeUIView` / re-render so the latest
        /// closure (and the latest store reference) wins.
        private var onDelete: ((UUID) -> Void)?

        /// The annotation the user just tapped — captured here so the
        /// menu builder in `editMenuInteraction(_:menuFor:)` can read
        /// it without threading state through the configuration's
        /// identifier. Cleared after the menu dismisses.
        private var pendingAnnotationID: UUID?

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        deinit {
            // Defensive — selector-style observers are auto-removed on
            // dealloc since iOS 9, but the explicit cleanup makes the
            // intent obvious to readers.
            NotificationCenter.default.removeObserver(self)
        }

        /// Called from `PDFCanvas.makeUIView`. Caches the host view and
        /// the latest delete callback, and installs the edit-menu
        /// interaction on first attach. Safe to call again on re-render
        /// — only the callback updates after first install.
        func attach(pdfView: PDFView, onDelete: @escaping (UUID) -> Void) {
            self.pdfView = pdfView
            self.onDelete = onDelete

            if editMenuInteraction == nil {
                let interaction = UIEditMenuInteraction(delegate: self)
                pdfView.addInteraction(interaction)
                editMenuInteraction = interaction
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

            pendingAnnotationID = id
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
                guard let id = pendingAnnotationID else { return nil }
                let remove = UIAction(
                    title: AppStrings.Library.annotationRemoveAction,
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.onDelete?(id)
                    self?.pendingAnnotationID = nil
                }
                // Suggested actions cover copy/lookup/share — keep them
                // so the menu still feels like the system one; append
                // Remove at the end so destructive lives last per HIG.
                return UIMenu(children: suggestedActions + [remove])
            }
        }

        nonisolated func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            willDismissMenuFor configuration: UIEditMenuConfiguration,
            animator: any UIEditMenuInteractionAnimating
        ) {
            MainActor.assumeIsolated {
                pendingAnnotationID = nil
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

    @State private var parseResult: ParseResult = .parsing
    /// Bumped on every highlight-button tap so `PDFCanvas` re-runs
    /// selection extraction. `nil` means "no request yet"; subsequent
    /// taps produce a new id that the canvas coordinator dedupes
    /// against.
    @State private var highlightTrigger: HighlightTrigger?

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
                ZStack(alignment: .bottomTrailing) {
                    PDFCanvas(
                        document: document,
                        annotations: annotations,
                        currentPage: $currentPage,
                        highlightTrigger: highlightTrigger,
                        onHighlightExtracted: onHighlightExtracted,
                        onAnnotationDeleteRequested: onAnnotationDeleteRequested
                    )

                    highlightButton
                        .padding(DesignSystem.standard.spacing.lg)
                }

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

    /// Floating highlighter button. Always enabled — Phase 4b
    /// deliberately skips selection-state tracking (PDFView doesn't
    /// expose a clean "selection changed" hook short of polling).
    /// Tap with no selection is a silent no-op; tap with selection
    /// fires the extract pipeline. Users learn the contract on first
    /// try.
    private var highlightButton: some View {
        Button {
            highlightTrigger = HighlightTrigger(id: UUID())
        } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(DesignSystem.standard.colors.inkPure)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(DesignSystem.standard.colors.paper)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    DesignSystem.standard.colors.rule,
                                    lineWidth: DesignSystem.standard.layout.borderWidth
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Library.highlightSelectionButton)
    }
}
