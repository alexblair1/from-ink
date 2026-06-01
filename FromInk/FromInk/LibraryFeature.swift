import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Library")

/// Owns the notebook + folder list as `Sendable` snapshot value types.
/// Composed into surfaces that need to display, create, or mutate
/// notebooks — today that's `HomeFeature`; future consumers include
/// cross-notebook search, the dispatch panel's "open notebook" links,
/// and any settings export view.
///
/// **What this feature does NOT own:**
/// - Search input text — surfaces own their own search bars and pass
///   a filter predicate at render time.
/// - Active-notebook presentation (`fullScreenCover` etc.) — that's a
///   surface concern; LibraryFeature only fires `delegate.notebookCreated`
///   for the parent to act on.
/// - Page-level data — `NotebookFeature` (Step 9) owns the page list
///   for an opened notebook.
struct LibraryFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var notebooks: [NotebookSnapshot] = []
        var folders: [FolderSnapshot] = []
        /// Most-recently-opened PDFs (with `modifiedAt` fallback for
        /// never-opened entries). Sourced from
        /// `NotebookClient.fetchRecentPDFs(limit:)` and capped at
        /// `recentPDFsLimit`. Surfaces use this directly — there's no
        /// secondary "all PDFs" list today; when a full library page
        /// lands we'll add a parallel field rather than reusing this.
        var recentPDFs: [PDFDocumentSnapshot] = []

        /// Page size for `recentPDFs`. Enough to fill a horizontal
        /// scroller on the largest current device without thrashing the
        /// store for a paginated load. Surfaces can read fewer than
        /// this; nothing reads more.
        var recentPDFsLimit: Int = 20

        /// Becomes true after the first `dataLoaded` action. Used by
        /// surfaces to distinguish "still loading" from "loaded empty".
        var hasLoadedOnce: Bool = false

        /// If `true` and the first load returns an empty notebook list,
        /// the reducer creates a default "My Notebook" so users have
        /// somewhere to start drawing. Toggleable for tests + previews
        /// that want to assert the empty-state UI.
        var shouldSeedIfEmpty: Bool = true
    }

    @CasePathable
    enum Action: Equatable {
        case onAppear
        case storeDidChange
        case dataLoaded(
            notebooks: [NotebookSnapshot],
            folders: [FolderSnapshot],
            recentPDFs: [PDFDocumentSnapshot]
        )
        case loadFailed(reason: String)

        // Notebook lifecycle (caller-initiated)
        case createNotebookRequested(title: String)
        case renameNotebookRequested(id: UUID, title: String)
        case deleteNotebookRequested(id: UUID)
        /// Bumps the notebook's `modifiedAt` so opening (without
        /// editing) bubbles it to the top of recency-sorted lists.
        /// Despite the legacy "opened" framing in earlier revisions,
        /// this maps to `notebookClient.touchNotebookModified` — there
        /// is no `lastOpenedAt` field on `Notebook` (that semantic
        /// lives on `PDFDocument` for PDFs).
        case touchNotebookActivated(id: UUID)
        case moveNotebookToFolderRequested(notebookID: UUID, folderID: UUID?)

        // PDF import (caller-initiated)
        case importPDFRequested(URL)

        // Folder lifecycle (caller-initiated)
        case createFolderRequested(name: String, parentID: UUID?)
        case deleteFolderRequested(id: UUID)

        // Delegate (consumed by parent surfaces)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// Fired after `NotebookClient.createNotebook` succeeds. Parents
            /// typically dismiss the new-notebook sheet and present the
            /// created notebook (`fullScreenCover` etc.). The snapshot is
            /// already in `state.notebooks` by the time this fires.
            case notebookCreated(NotebookSnapshot)
            /// Fired after a PDF import completes. `wasDuplicate == true`
            /// means the bytes matched an already-imported `PDFDocument`
            /// and the snapshot is the existing one (no new row was
            /// inserted); parents typically navigate to it and surface
            /// a small "already in your library" affordance. `false` is
            /// the new-import case.
            case pdfImported(PDFDocumentSnapshot, wasDuplicate: Bool)
            /// Fired when PDF import fails. `message` is the human-readable
            /// localized string ready for an alert body.
            case pdfImportFailed(message: String)
        }
    }

    @Dependency(\.notebookClient) var notebookClient
    @Dependency(\.importPDFService) var importPDFService

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    refresh(),
                    observeStoreChanges()
                )

            case .storeDidChange:
                return refresh()

            case .dataLoaded(let nbs, let folders, let pdfs):
                let wasFirstLoad = !state.hasLoadedOnce
                state.notebooks = nbs
                state.folders = folders
                state.recentPDFs = pdfs
                state.hasLoadedOnce = true
                if wasFirstLoad && state.shouldSeedIfEmpty && nbs.isEmpty {
                    return seedDefaultNotebook()
                }
                return .none

            case .loadFailed(let reason):
                log.error("Library load failed: \(reason)")
                return .none

            case .createNotebookRequested(let rawTitle):
                let title = rawTitle.isEmpty ? AppStrings.Common.untitled : rawTitle
                return .run { send in
                    do {
                        let snap = try await notebookClient.createNotebook(title, nil, .notebook)
                        await send(.delegate(.notebookCreated(snap)))
                    } catch {
                        log.error("createNotebook failed: \(error.localizedDescription)")
                    }
                }

            case .renameNotebookRequested(let id, let title):
                return .run { _ in
                    try await notebookClient.renameNotebook(id, title)
                }

            case .deleteNotebookRequested(let id):
                return .run { _ in
                    try await notebookClient.deleteNotebook(id)
                }

            case .touchNotebookActivated(let id):
                return .run { _ in
                    try await notebookClient.touchNotebookModified(id)
                }

            case .moveNotebookToFolderRequested(let notebookID, let folderID):
                return .run { _ in
                    try await notebookClient.moveNotebookToFolder(notebookID, folderID)
                }

            case .importPDFRequested(let url):
                return .run { send in
                    do {
                        let draft = try await importPDFService.importPDF(url)
                        do {
                            let snap = try await notebookClient.importPDF(draft, nil)
                            await send(.delegate(.pdfImported(snap, wasDuplicate: false)))
                        } catch NotebookClientError.pdfAlreadyImported(let existingID) {
                            // Dedup hit. Walk the full-PDFs list and pick
                            // out the matching ID — cheap on libraries of
                            // realistic size, and avoids adding a
                            // dedicated by-ID PDF fetch to the client.
                            let allPDFs = try await notebookClient.fetchAllPDFs()
                            if let snap = allPDFs.first(where: { $0.id == existingID }) {
                                await send(.delegate(.pdfImported(snap, wasDuplicate: true)))
                            } else {
                                // Existing row vanished between dedup
                                // check and re-fetch (delete race).
                                // Surface as a generic failure rather
                                // than silently doing nothing.
                                log.error("importPDF dedup pointed at id=\(existingID) but no matching PDF in fetchAllPDFs")
                                await send(.delegate(.pdfImportFailed(
                                    message: AppStrings.Library.importPDFInvalidMessage
                                )))
                            }
                        }
                    } catch let importError as ImportPDFError {
                        log.error("importPDF flow failed: \(String(describing: importError))")
                        await send(.delegate(.pdfImportFailed(message: importError.userMessage)))
                    } catch {
                        log.error("importPDF flow failed (unknown): \(error.localizedDescription)")
                        await send(.delegate(.pdfImportFailed(
                            message: AppStrings.Library.importPDFInvalidMessage
                        )))
                    }
                }

            case .createFolderRequested(let name, let parentID):
                return .run { _ in
                    _ = try await notebookClient.createFolder(name, parentID)
                }

            case .deleteFolderRequested(let id):
                return .run { _ in
                    try await notebookClient.deleteFolder(id)
                }

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - Effects

    private func refresh() -> Effect<Action> {
        .run { send in
            do {
                async let notebooksTask = notebookClient.fetchAllNotebooks()
                async let foldersTask = notebookClient.fetchAllFolders()
                // The PDFs limit is read by the reducer from
                // `State.recentPDFsLimit`; effect closures can't see
                // state, so the cap is duplicated here. Keep in sync
                // by reading `LibraryFeature.State()` defaults or
                // bumping both at once.
                async let pdfsTask = notebookClient.fetchRecentPDFs(20)
                let (nbs, folders, pdfs) = try await (notebooksTask, foldersTask, pdfsTask)
                await send(.dataLoaded(notebooks: nbs, folders: folders, recentPDFs: pdfs))
            } catch {
                await send(.loadFailed(reason: String(describing: error)))
            }
        }
        .cancellable(id: "libraryRefresh", cancelInFlight: true)
    }

    private func observeStoreChanges() -> Effect<Action> {
        .run { send in
            for await _ in ModelStoreObserver.observe() {
                await send(.storeDidChange)
            }
        }
        .cancellable(id: "libraryStoreObservation", cancelInFlight: true)
    }

    /// Creates a default "My Notebook" on a brand-new install so the
    /// user has somewhere to draw. The `storeDidChange` observation
    /// will pick up the insert and trigger a `refresh` automatically;
    /// we don't need to send `.dataLoaded` here ourselves.
    private func seedDefaultNotebook() -> Effect<Action> {
        .run { _ in
            do {
                _ = try await notebookClient.createNotebook(
                    AppStrings.Library.myNotebook,
                    nil,
                    .notebook
                )
            } catch {
                log.error("Default notebook seed failed: \(error.localizedDescription)")
            }
        }
    }
}
