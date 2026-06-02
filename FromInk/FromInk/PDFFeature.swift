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
        /// Renders are diff-by-id reconciled in `PDFCanvas`; the
        /// upcoming highlight-creation UI (Phase 4b) appends new
        /// snapshots here so they render immediately without round-
        /// tripping through a re-fetch.
        ///
        /// Annotation-load failure is non-fatal: the viewer renders
        /// the PDF without overlay annotations, with a logged warning.
        /// Treating it as fatal would hide the document for a
        /// recoverable issue (sync race, transient SwiftData hiccup).
        var annotations: [PDFAnnotationSnapshot] = []

        // MARK: - Search

        /// `true` when the search affordance is open — the top bar
        /// shows the search field instead of the title. Toggled by
        /// `.searchToggled`; clearing the field doesn't auto-close so
        /// the user can refine without losing focus.
        var isSearchActive: Bool = false
        /// The live search query the user has typed. Submission (return
        /// key) emits `.searchSubmitted` and fires the trigger.
        var searchQuery: String = ""
        /// Total matches the canvas found for the last submitted query.
        /// Zero means "no matches" or "no query submitted yet" — the
        /// label disambiguates by checking `searchQuery` non-empty.
        var searchResultCount: Int = 0
        /// 1-based index of the currently-anchored match (matches the
        /// "3 / 12" label). Zero when no match is anchored.
        var currentMatchIndex: Int = 0
        /// One-shot trigger consumed by `PDFCanvas` to run `findString`.
        /// `nil` resets after the canvas reports back so a re-render
        /// during a stable trigger doesn't re-search.
        var searchTrigger: SearchTrigger?
        /// One-shot trigger consumed by `PDFCanvas` to advance the
        /// internal selection cursor.
        var gotoMatchTrigger: GotoMatchTrigger?

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
        /// User tapped the dismiss chrome. Parent observes this via
        /// presentation action and clears its `@Presents` slot.
        case dismissTapped
        /// Coordinator reports a new visible page. State stores it for
        /// future annotation scoping; today nothing else reads it.
        case pageChanged(Int)

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
                // render. If the store throws (rare; sync race), we log
                // and let the missing record reappear on next
                // listForPDF.
                state.annotations.removeAll { $0.id == id }
                return .run { send in
                    do {
                        try await annotationStore.delete(id)
                        await send(.annotationDeleted(id))
                    } catch {
                        log.error("annotationStore.delete failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .private)")
                    }
                }

            case .annotationDeleted:
                // Completion signal — state was mutated optimistically
                // in `.deleteAnnotation`. No-op here.
                return .none

            case .dismissTapped:
                // Parent owns dismiss — clears the @Presents slot.
                return .none

            case .searchToggled:
                state.isSearchActive.toggle()
                if !state.isSearchActive {
                    // Closing search clears the query so the next open
                    // starts clean. Don't fire a search trigger — the
                    // canvas's stale selections clear when the user
                    // submits the next query or when the trigger goes
                    // back to nil mid-render.
                    state.searchQuery = ""
                    state.searchResultCount = 0
                    state.currentMatchIndex = 0
                    state.searchTrigger = nil
                    state.gotoMatchTrigger = nil
                }
                return .none

            case .searchQueryChanged(let query):
                state.searchQuery = query
                // Don't fire on every keystroke — wait for return. An
                // empty field after a non-empty one shouldn't preserve
                // stale counts in the label.
                if query.isEmpty {
                    state.searchResultCount = 0
                    state.currentMatchIndex = 0
                }
                return .none

            case .searchSubmitted:
                let query = state.searchQuery
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return .none }
                state.searchTrigger = SearchTrigger(id: uuid(), query: query)
                return .none

            case .searchResultsLoaded(let count, let currentIndex):
                state.searchResultCount = count
                state.currentMatchIndex = currentIndex
                return .none

            case .stepMatch(let direction):
                // No-op if there's nothing to step through — guards the
                // canvas from a spurious goto on an empty result set.
                guard state.searchResultCount > 0 else { return .none }
                state.gotoMatchTrigger = GotoMatchTrigger(id: uuid(), direction: direction)
                return .none

            case .currentMatchChanged(let index):
                state.currentMatchIndex = index
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
