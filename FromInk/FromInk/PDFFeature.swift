import ComposableArchitecture
import CoreGraphics
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "PDFFeature")

/// A single PDF-text-line worth of highlight payload — the unit
/// `AnnotationStore.createHighlight` consumes. A `PDFSelection` that
/// spans multiple lines is split into one `HighlightLine` per
/// `selectionsByLine()` segment so each line gets its own
/// `PDFAnnotation` record (the rendering matches Acrobat / Books:
/// per-line rectangles rather than one giant bounding box).
///
/// Bounds are **normalized 0..1 in the PDF page's cropBox** — same
/// coordinate space as `PDFAnnotationSnapshot.bounds`. The conversion
/// happens at extraction time inside `PDFCanvas`.
struct HighlightLine: Equatable, Sendable {
    let pageIndex: Int
    let bounds: CGRect
    let extractedText: String
}

/// One-shot signal asking `PDFCanvas` to run the given query against
/// the loaded `PDFDocument`. The wrapping UUID forces SwiftUI to
/// propagate state changes — the coordinator dedupes by comparing
/// against the last consumed id, so identical queries fired twice
/// still re-run.
struct SearchTrigger: Equatable, Sendable {
    let id: UUID
    let query: String
}

/// One-shot signal asking `PDFCanvas` to advance its internal search
/// cursor. The coordinator owns the `[PDFSelection]` result list
/// (PDFSelection isn't Sendable) and applies `PDFView.go(to:)` against
/// the next/previous match. Cycles at the ends.
struct GotoMatchTrigger: Equatable, Sendable {
    enum Direction: Sendable { case next, previous }
    let id: UUID
    let direction: Direction
}

/// One-shot signal asking `PDFCanvas` to serialize its mounted
/// `PKCanvasView`'s drawing and report the bytes + bounds via
/// `onDrawingCommitted`. The reducer fires this on `drawingDoneTapped`;
/// the coordinator does the work imperatively because `PKDrawing`
/// isn't Sendable.
struct DrawingCommitTrigger: Equatable, Sendable {
    let id: UUID
}

/// Tool selection for the modal PDF drawing toolbar. Phase 5c adds
/// pencil + marker; lasso + width pickers land in 5d.
enum PDFDrawingTool: Equatable, Sendable {
    case pen
    case pencil
    case marker
    case eraser
}

/// One-shot signal asking `PDFCanvas` to call `undoManager.undo()`
/// (or `.redo()`) on the mounted `PKCanvasView`. Mirrors the
/// trigger-id pattern used by search and commit so a stable value
/// across re-renders doesn't re-fire.
struct DrawingUndoTrigger: Equatable, Sendable {
    enum Direction: Sendable { case undo, redo }
    let id: UUID
    let direction: Direction
}

/// In-PDF search state. The status machine collapses six flat
/// bool/int fields into a single discriminated union so impossible
/// states (`count == 0 && current > 0`, `isActive == false &&
/// query.nonEmpty`) can't be expressed.
struct PDFSearch: Equatable {
    enum Status: Equatable {
        /// The search affordance is closed — the top bar shows the
        /// title, not the field.
        case inactive
        /// The field is open and either empty or holding an unsubmitted
        /// draft. Submission moves to `.results` or `.noMatches`.
        case typing(query: String)
        /// The last submitted query returned at least one match.
        /// `current` is 1-based to match the UI counter.
        case results(query: String, count: Int, current: Int)
        /// The last submitted query returned no matches.
        case noMatches(query: String)
    }

    var status: Status = .inactive
    /// One-shot consumed by `PDFCanvas` to run `findString`. The
    /// coordinator dedupes by id so a stable trigger across SwiftUI
    /// re-renders doesn't re-search.
    var searchTrigger: SearchTrigger?
    /// One-shot consumed by `PDFCanvas` to step the result cursor.
    var gotoMatchTrigger: GotoMatchTrigger?

    var isActive: Bool {
        if case .inactive = status { return false }
        return true
    }

    /// The query as displayed in the field. Empty in `.inactive`;
    /// otherwise the latest typed or submitted query.
    var query: String {
        switch status {
        case .inactive: return ""
        case .typing(let q), .results(let q, _, _), .noMatches(let q): return q
        }
    }

    /// 1-based current match for the counter label, or 0 when no
    /// match is anchored.
    var currentMatchIndex: Int {
        if case .results(_, _, let current) = status { return current }
        return 0
    }

    /// Total matches for the counter label, or 0 when nothing's been
    /// submitted yet / no matches.
    var resultCount: Int {
        if case .results(_, let count, _) = status { return count }
        return 0
    }

    /// Whether the counter label should render at all. Pre-submit
    /// (no query, or `.typing` only) the label hides; once a result
    /// status has been seen, it appears.
    var hasReportedResults: Bool {
        switch status {
        case .results, .noMatches: return true
        case .inactive, .typing: return false
        }
    }
}

/// Owns the open PDF viewer state. Presented as a fullScreenCover from
/// `HomeFeature` (and, later, from a notebook page's link tap). Loads
/// the PDF bytes once on `.onAppear` via `NotebookClient.fetchPDFData`
/// — the bytes don't ride through any snapshot, so this is the one
/// hop where `sourcePDFData` is materialized.
///
/// **Manual `Reducer` conformance** — the `@Reducer` macro is
/// incompatible with this project's `MainActor` isolation. See
/// `ToolbarFeature` for the canonical example.
struct PDFFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        let pdfID: UUID
        /// Pre-loaded from the `ImportedPDFSnapshot` at presentation
        /// time so the title bar can render immediately while bytes
        /// load.
        let title: String
        let pageCount: Int
        var loadState: LoadState = .loading
        /// Currently-visible page index (0-based). Updated by the
        /// `PDFCanvas` coordinator on visible-page changes. Phase 4
        /// (annotations) uses this to scope rendering.
        var currentPage: Int = 0

        /// Annotations owned by this PDF, loaded once on `.onAppear`.
        /// New highlights from the user's selection are appended in
        /// `.highlightCreated`; deletions strip optimistically in
        /// `.deleteAnnotation`. The reconcile loop in `PDFCanvas`
        /// diff-renders this array against the PDFKit annotation tree
        /// on every state change.
        ///
        /// Annotation-load failure is non-fatal: the viewer renders
        /// the PDF without overlay annotations, with a logged warning.
        /// Treating it as fatal would hide the document for a
        /// recoverable issue (sync race, transient SwiftData hiccup).
        var annotations: [PDFAnnotationSnapshot] = []

        /// In-PDF search state. Substate keeps the flat-field churn
        /// out of `PDFFeature.State` and rules out impossible
        /// combinations at the type level.
        var search: PDFSearch = PDFSearch()

        // MARK: - Drawing mode

        /// `true` when the user is in modal drawing mode — a
        /// `PKCanvasView` overlays the visible page and the bottom
        /// toolbar replaces normal chrome. While active, search and
        /// page navigation are locked.
        var isDrawingActive: Bool = false
        /// Active drawing tool. Resets to `.pen` on every fresh entry
        /// into drawing mode so the tool doesn't carry stale state
        /// across sessions.
        var drawingTool: PDFDrawingTool = .pen
        /// Active ink color. Resets to black on every fresh entry into
        /// drawing mode. The eraser ignores color; the marker
        /// translucently applies it. `.blackText` is opaque so PKInk's
        /// pen and pencil render naturally.
        var drawingInkColor: PDFAnnotationColor = .blackText
        /// One-shot fired by `.drawingDoneTapped`. The canvas
        /// coordinator serializes its `PKCanvasView` drawing on
        /// receipt and dispatches `.drawingCommitted`.
        var drawingCommitTrigger: DrawingCommitTrigger?
        /// One-shot fired by `.drawingUndoTapped` / `.drawingRedoTapped`.
        /// The canvas coordinator calls the matching undoManager
        /// method on the mounted `PKCanvasView`.
        var drawingUndoTrigger: DrawingUndoTrigger?

        enum LoadState: Equatable {
            case loading
            /// Bytes are loaded and ready to hand to PDFKit. Stored as
            /// `Data` here; the `PDFCanvas` does the heavy
            /// `PDFKit.PDFDocument(data:)` parse off-actor.
            case loaded(Data)
            /// Load failed — `sourcePDFData` was nil (corrupted import)
            /// or the row was deleted between presentation and load.
            /// `message` is the localized alert body.
            case failed(message: String)
        }
    }

    @CasePathable
    enum Action: Equatable {
        case onAppear
        /// Result of `notebookClient.fetchPDFData(id:)`. `nil` means
        /// the row had no `sourcePDFData` (or the row vanished) — the
        /// reducer transitions to `.failed`.
        case dataLoaded(Data?)
        /// `notebookClient.fetchPDFData` threw. Logs and transitions to
        /// `.failed` with the localized message.
        case loadFailed(String)
        /// Result of `annotationStore.listForPDF(id:)`. Empty array is
        /// the normal "no annotations yet" state, distinct from a
        /// load failure (which logs and leaves the array empty —
        /// non-fatal so the PDF still renders).
        case annotationsLoaded([PDFAnnotationSnapshot])
        /// User tapped the highlight button while text was selected.
        /// `PDFCanvas` extracted the selection into one
        /// `HighlightLine` per text line and normalized the bounds.
        /// The reducer fans out per-line `createHighlight` calls and
        /// appends each returned snapshot via `.highlightCreated`.
        case createHighlightFromSelection([HighlightLine])
        /// Result of `annotationStore.createHighlight`. Appended to
        /// `state.annotations` so the reconcile loop renders it
        /// immediately — no round-trip through `listForPDF`.
        case highlightCreated(PDFAnnotationSnapshot)
        /// User tapped one of our annotations and chose "Remove" from
        /// the edit menu. The reducer fires `annotationStore.delete`
        /// and removes the snapshot optimistically so the reconcile
        /// loop strips the PDFKit annotation on the next render.
        case deleteAnnotation(UUID)
        /// Confirms the optimistic remove — emitted from the delete
        /// effect's success path. The state mutation already happened
        /// in `.deleteAnnotation`; this action exists for parity with
        /// the create flow and gives the test store an explicit
        /// completion signal.
        case annotationDeleted(UUID)
        /// Delete effect threw. Restores the snapshot to
        /// `state.annotations` at its original sort position so the
        /// user doesn't see a phantom-deleted highlight that
        /// reappears later. The snapshot is the one removed in
        /// `.deleteAnnotation`; equality includes id, so a stale
        /// restore (e.g. user re-deleted before failure landed) is
        /// idempotent.
        case deleteAnnotationFailed(PDFAnnotationSnapshot)
        /// User tapped the dismiss chrome. Parent observes this via
        /// presentation action and clears its `@Presents` slot.
        case dismissTapped
        /// Coordinator reports a new visible page. State stores it for
        /// future annotation scoping; today nothing else reads it.
        case pageChanged(Int)

        // MARK: - Drawing mode

        /// User tapped the Draw button in the top bar. Transitions to
        /// modal drawing mode — mounts the `PKCanvasView` overlay,
        /// swaps in the drawing chrome.
        case drawingModeEntered
        /// User picked a different tool in the drawing toolbar.
        case drawingToolChanged(PDFDrawingTool)
        /// User picked a different ink color in the drawing palette.
        case drawingInkColorChanged(PDFAnnotationColor)
        /// User tapped the undo or redo button in the drawing top bar.
        /// Fires the matching trigger so the canvas's undoManager
        /// runs imperatively. The buttons are always tappable — if
        /// there's nothing to undo, the canvas no-ops silently.
        case drawingUndoTapped
        case drawingRedoTapped
        /// User tapped Done. Fires the commit trigger so the canvas
        /// serializes its drawing.
        case drawingDoneTapped
        /// User tapped Cancel. Discards the in-progress drawing and
        /// exits drawing mode without writing to SwiftData.
        case drawingCancelTapped
        /// Canvas reports back from the commit trigger. `bytes` is
        /// `PKDrawing.dataRepresentation()`; `bounds` is normalized
        /// 0..1 in the PDF page cropBox; `pageIndex` is the page the
        /// drawing was placed on. Empty drawings (no strokes) skip
        /// the create call and just exit drawing mode.
        case drawingCommitted(bytes: Data, bounds: CGRect, pageIndex: Int)
        /// `annotationStore.createPencil` succeeded. The snapshot is
        /// appended to `state.annotations`; drawing mode exits.
        case drawingSnapshotCreated(PDFAnnotationSnapshot)
        /// `annotationStore.createPencil` threw. Drawing mode exits
        /// anyway — the user's intent was to commit, and leaving the
        /// modal up after a sync error would be more confusing than
        /// dropping back to the document.
        case drawingCommitFailed

        // MARK: - Search

        /// User tapped the magnifying-glass chip / Close-Search button
        /// in the top bar. Toggles `isSearchActive`; closing also
        /// clears the query, count, and current-match cursor.
        case searchToggled
        /// User typed in the search field — onChange of the bound
        /// string.
        case searchQueryChanged(String)
        /// User pressed return. If the query is non-empty, fires the
        /// search trigger so the canvas runs `findString`.
        case searchSubmitted
        /// Canvas reports back after running `findString`. `count` is
        /// total matches; `currentIndex` is 1-based (canvas jumped to
        /// the first match) or 0 for no matches.
        case searchResultsLoaded(count: Int, currentIndex: Int)
        /// User tapped one of the up/down chevrons. Fires the
        /// goto-match trigger.
        case stepMatch(GotoMatchTrigger.Direction)
        /// Canvas reports back after applying a step. New 1-based
        /// index.
        case currentMatchChanged(Int)
    }

    @Dependency(\.notebookClient) var notebookClient
    @Dependency(\.annotationStore) var annotationStore
    @Dependency(\.calendarContext) var cal
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let id = state.pdfID
                return .run { send in
                    // Touch lastOpenedAt first so the home Recent shelf
                    // re-sorts even if the bytes fail to load — opening
                    // counts as activity.
                    do { try await notebookClient.touchPDFOpened(id) }
                    catch { log.error("touchPDFOpened failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)") }

                    // Bytes and annotations are independent — load
                    // them in parallel so the viewer doesn't gate
                    // either on the other. Bytes failure transitions
                    // loadState to .failed; annotation failure logs
                    // and leaves the array empty (PDF still renders,
                    // without overlay annotations).
                    async let bytes: Void = loadBytes(id: id, send: send)
                    async let annotations: Void = loadAnnotations(id: id, send: send)
                    _ = await (bytes, annotations)
                }
                .cancellable(id: "pdfLoad-\(id)", cancelInFlight: true)

            case .dataLoaded(.some(let data)):
                state.loadState = .loaded(data)
                return .none

            case .dataLoaded(.none):
                // `sourcePDFData` was nil or the row vanished between
                // presentation and load. Log the id for diagnostics;
                // surface a viewer-specific message (the import-time
                // "couldn't read this file as a PDF" copy is misleading
                // here — the read succeeded, the bytes were missing).
                let id = state.pdfID
                log.error("PDF load failed: fetchPDFData returned nil for \(id, privacy: .public)")
                state.loadState = .failed(message: AppStrings.Library.pdfViewerLoadFailedMessage)
                return .none

            case .loadFailed(let message):
                // Bind the carried error description so it shows up in
                // diagnostics. The user-facing message is the
                // viewer-specific string — the raw error description
                // is rarely user-actionable.
                log.error("PDF load failed: \(message, privacy: .private)")
                state.loadState = .failed(message: AppStrings.Library.pdfViewerLoadFailedMessage)
                return .none

            case .pageChanged(let index):
                state.currentPage = index
                return .none

            case .annotationsLoaded(let annotations):
                state.annotations = annotations
                return .none

            case .createHighlightFromSelection(let lines):
                guard !lines.isEmpty else { return .none }
                let pdfID = state.pdfID
                let now = cal.now()
                return .run { send in
                    // Sequential rather than parallel — each create is
                    // a fast SwiftData write, and serializing them keeps
                    // the lines' createdAt strictly ordered (matters
                    // for the `sortBy: createdAt` in `listForPDF`).
                    // A per-line failure logs and continues so a
                    // mid-selection sync hiccup doesn't drop the rest
                    // of the user's highlight.
                    for line in lines {
                        do {
                            let snapshot = try await annotationStore.createHighlight(
                                pdfID,
                                line.pageIndex,
                                line.bounds,
                                line.extractedText,
                                .yellowHighlight,
                                now
                            )
                            await send(.highlightCreated(snapshot))
                        } catch {
                            log.error("createHighlight failed for pdf=\(pdfID, privacy: .public) page=\(line.pageIndex, privacy: .public): \(error.localizedDescription, privacy: .private)")
                        }
                    }
                }

            case .highlightCreated(let snapshot):
                state.annotations.append(snapshot)
                return .none

            case .deleteAnnotation(let id):
                // Optimistic — strip the snapshot now so the reconcile
                // loop removes the PDFKit annotation on the next
                // render. The record we just removed is captured so
                // the failure path can restore it (sync race, transient
                // SwiftData hiccup). Without restore, the user would
                // see a phantom-deleted highlight until the viewer
                // reopens — there's no second `listForPDF` today.
                let restoreOnFailure = state.annotations.first { $0.id == id }
                state.annotations.removeAll { $0.id == id }
                return .run { send in
                    do {
                        try await annotationStore.delete(id)
                        await send(.annotationDeleted(id))
                    } catch {
                        log.error("annotationStore.delete failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .private)")
                        if let restore = restoreOnFailure {
                            await send(.deleteAnnotationFailed(restore))
                        }
                    }
                }

            case .annotationDeleted:
                // Completion signal — state was mutated optimistically
                // in `.deleteAnnotation`. No-op here.
                return .none

            case .deleteAnnotationFailed(let snapshot):
                // Restore the snapshot the user thought they deleted.
                // Inserted at its original sort position (by createdAt)
                // so it lands where listForPDF would have placed it.
                let index = state.annotations.firstIndex { $0.createdAt > snapshot.createdAt }
                    ?? state.annotations.endIndex
                state.annotations.insert(snapshot, at: index)
                return .none

            case .dismissTapped:
                // Parent owns dismiss — clears the @Presents slot.
                return .none

            // MARK: - Drawing mode

            case .drawingModeEntered:
                state.isDrawingActive = true
                state.drawingTool = .pen
                state.drawingInkColor = .blackText
                state.drawingCommitTrigger = nil
                state.drawingUndoTrigger = nil
                return .none

            case .drawingToolChanged(let tool):
                guard state.isDrawingActive else { return .none }
                state.drawingTool = tool
                return .none

            case .drawingInkColorChanged(let color):
                guard state.isDrawingActive else { return .none }
                state.drawingInkColor = color
                return .none

            case .drawingUndoTapped:
                guard state.isDrawingActive else { return .none }
                state.drawingUndoTrigger = DrawingUndoTrigger(id: uuid(), direction: .undo)
                return .none

            case .drawingRedoTapped:
                guard state.isDrawingActive else { return .none }
                state.drawingUndoTrigger = DrawingUndoTrigger(id: uuid(), direction: .redo)
                return .none

            case .drawingDoneTapped:
                guard state.isDrawingActive else { return .none }
                state.drawingCommitTrigger = DrawingCommitTrigger(id: uuid())
                return .none

            case .drawingCancelTapped:
                state.isDrawingActive = false
                state.drawingCommitTrigger = nil
                state.drawingUndoTrigger = nil
                return .none

            case .drawingCommitted(let bytes, let bounds, let pageIndex):
                // Empty drawing — user entered drawing mode but didn't
                // ink anything. Just exit; no SwiftData write.
                guard !bytes.isEmpty else {
                    state.isDrawingActive = false
                    state.drawingCommitTrigger = nil
                    return .none
                }
                let pdfID = state.pdfID
                let now = cal.now()
                return .run { send in
                    do {
                        let snapshot = try await annotationStore.createPencil(
                            pdfID, pageIndex, bounds, bytes, .blackText, now
                        )
                        await send(.drawingSnapshotCreated(snapshot))
                    } catch {
                        log.error("createPencil failed for pdf=\(pdfID, privacy: .public) page=\(pageIndex, privacy: .public): \(error.localizedDescription, privacy: .private)")
                        await send(.drawingCommitFailed)
                    }
                }

            case .drawingSnapshotCreated(let snapshot):
                state.annotations.append(snapshot)
                state.isDrawingActive = false
                state.drawingCommitTrigger = nil
                state.drawingUndoTrigger = nil
                return .none

            case .drawingCommitFailed:
                state.isDrawingActive = false
                state.drawingCommitTrigger = nil
                state.drawingUndoTrigger = nil
                return .none

            case .searchToggled:
                if state.search.isActive {
                    // Close: reset the substate. Triggers go to nil so
                    // the canvas's `lastConsumed*` ids don't keep
                    // matching old triggers across a close-reopen.
                    state.search = PDFSearch()
                } else {
                    state.search.status = .typing(query: "")
                }
                return .none

            case .searchQueryChanged(let raw):
                // Trim leading/trailing whitespace at the source so
                // the typing state and the submit guard agree on what
                // counts as empty. An all-whitespace string is
                // semantically empty for search purposes.
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard state.search.isActive else { return .none }
                state.search.status = .typing(query: trimmed)
                return .none

            case .searchSubmitted:
                let query = state.search.query
                guard !query.isEmpty else { return .none }
                // Stay in `.typing` until the canvas reports results;
                // the typing status preserves the current query so the
                // field doesn't appear to clear during the search.
                state.search.searchTrigger = SearchTrigger(id: uuid(), query: query)
                return .none

            case .searchResultsLoaded(let count, let currentIndex):
                // Transition the status based on the canvas report.
                // `query` comes from current state — the canvas doesn't
                // round-trip it.
                let query = state.search.query
                guard !query.isEmpty else { return .none }
                if count > 0 {
                    state.search.status = .results(
                        query: query,
                        count: count,
                        current: currentIndex
                    )
                } else {
                    state.search.status = .noMatches(query: query)
                }
                return .none

            case .stepMatch(let direction):
                // Only meaningful when results are anchored. Guards the
                // canvas from a spurious goto and rejects taps on a
                // `.typing` / `.noMatches` status.
                guard case .results = state.search.status else { return .none }
                state.search.gotoMatchTrigger = GotoMatchTrigger(
                    id: uuid(),
                    direction: direction
                )
                return .none

            case .currentMatchChanged(let index):
                // Update the anchored cursor without changing query or
                // count. No-op if the status drifted away from
                // `.results` between step request and reply.
                if case .results(let query, let count, _) = state.search.status {
                    state.search.status = .results(
                        query: query,
                        count: count,
                        current: index
                    )
                }
                return .none
            }
        }
    }

    // MARK: - Effect helpers

    /// Loads the PDF bytes and dispatches the right outcome action.
    /// Extracted from `.onAppear` so the parallel `async let` reads
    /// cleanly without a nested do/catch tower.
    private func loadBytes(id: UUID, send: Send<Action>) async {
        do {
            let data = try await notebookClient.fetchPDFData(id)
            await send(.dataLoaded(data))
        } catch {
            log.error("fetchPDFData failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await send(.loadFailed(error.localizedDescription))
        }
    }

    /// Loads the PDF's annotations. Failure is non-fatal: log and
    /// leave the array empty so the viewer still renders the document.
    /// The user sees no annotations rather than a crash / dead viewer
    /// for a recoverable issue (sync race, transient SwiftData hiccup).
    private func loadAnnotations(id: UUID, send: Send<Action>) async {
        do {
            let annotations = try await annotationStore.listForPDF(id)
            await send(.annotationsLoaded(annotations))
        } catch {
            log.error("annotationStore.listForPDF failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Don't transition loadState — empty annotations isn't a
            // viewer failure. Leaving `state.annotations` at its default
            // empty array.
        }
    }
}
