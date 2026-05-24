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
        case dataLoaded(notebooks: [NotebookSnapshot], folders: [FolderSnapshot])
        case loadFailed(reason: String)

        // Notebook lifecycle (caller-initiated)
        case createNotebookRequested(title: String)
        case renameNotebookRequested(id: UUID, title: String)
        case deleteNotebookRequested(id: UUID)
        case touchNotebookOpened(id: UUID)
        case moveNotebookToFolderRequested(notebookID: UUID, folderID: UUID?)

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
        }
    }

    @Dependency(\.notebookClient) var notebookClient

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

            case .dataLoaded(let nbs, let folders):
                let wasFirstLoad = !state.hasLoadedOnce
                state.notebooks = nbs
                state.folders = folders
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

            case .touchNotebookOpened(let id):
                return .run { _ in
                    try await notebookClient.touchNotebookModified(id)
                }

            case .moveNotebookToFolderRequested(let notebookID, let folderID):
                return .run { _ in
                    try await notebookClient.moveNotebookToFolder(notebookID, folderID)
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
                let (nbs, folders) = try await (notebooksTask, foldersTask)
                await send(.dataLoaded(notebooks: nbs, folders: folders))
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
