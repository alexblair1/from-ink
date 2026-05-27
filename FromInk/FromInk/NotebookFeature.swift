import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Notebook")

/// Owns the page list for a single open notebook. Fetches `NotePageSnapshot`s
/// via `NotebookClient` on appear, observes `NSManagedObjectContextDidSave`
/// to refresh when pages are added/removed/transferred from elsewhere.
///
/// **Composition:** presented by `HomeFeature` via `@Presents var notebook`.
/// When the parent's `.notebookTapped` fires, it constructs this state with
/// `notebookID` and `notebookTitle` from the tapped library snapshot.
///
/// **First-page seeding:** when the first load returns no pages (a freshly
/// created notebook), the reducer auto-creates a blank page so the
/// canvas is never empty.
struct NotebookFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        let notebookID: UUID
        var notebookTitle: String
        var pages: [NotePageSnapshot] = []
        var currentIndex: Int = 0
        var hasLoadedOnce: Bool = false

        /// Toolbar lives at the notebook level (not per-page) so tool
        /// selection persists across page swipes and `ToolbarWiringView`
        /// renders once as a sibling of the `TabView`.
        var toolbar: ToolbarFeature.State = .init()

        /// Notebook-wide template selection. Owned here so the template
        /// picker panel (rendered at notebook level alongside the toolbar)
        /// can write it and every page reads the same value.
        var activeTemplate: CanvasTemplate = .none

        init(notebookID: UUID, notebookTitle: String) {
            self.notebookID = notebookID
            self.notebookTitle = notebookTitle
        }
    }

    @CasePathable
    enum Action: Equatable {
        case onAppear
        case storeDidChange
        case pagesLoaded([NotePageSnapshot])
        case addPageTapped
        case pageCreated(NotePageSnapshot)
        case currentIndexChanged(Int)
        case templateSelected(CanvasTemplate)
        case toolbar(ToolbarFeature.Action)
    }

    @Dependency(\.notebookClient) var notebookClient

    var body: some Reducer<State, Action> {
        Scope(state: \.toolbar, action: \.toolbar) {
            ToolbarFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    refresh(notebookID: state.notebookID),
                    observeStoreChanges(),
                    .send(.toolbar(.onAppear))
                )

            case .storeDidChange:
                return refresh(notebookID: state.notebookID)

            case .pagesLoaded(let pages):
                let wasFirstLoad = !state.hasLoadedOnce
                state.pages = pages
                state.hasLoadedOnce = true
                // Clamp the current index if pages shrank out from under us.
                if state.currentIndex >= pages.count {
                    state.currentIndex = max(0, pages.count - 1)
                }
                if wasFirstLoad && pages.isEmpty {
                    return seedFirstPage(notebookID: state.notebookID)
                }
                return .none

            case .addPageTapped:
                let id = state.notebookID
                return .run { send in
                    do {
                        let snap = try await notebookClient.createPage(id, "blank")
                        await send(.pageCreated(snap))
                    } catch {
                        log.error("addPageTapped: createPage failed — \(error.localizedDescription)")
                    }
                }

            case .pageCreated(let snap):
                // Optimistic insert + jump-to-page. The store-change
                // observation will refresh the list shortly; we pre-seed
                // so the TabView animates to the new page without waiting
                // for the notification round-trip.
                if !state.pages.contains(where: { $0.id == snap.id }) {
                    state.pages.append(snap)
                }
                if let idx = state.pages.firstIndex(where: { $0.id == snap.id }) {
                    state.currentIndex = idx
                }
                return .none

            case .currentIndexChanged(let idx):
                state.currentIndex = idx
                return .none

            case .templateSelected(let template):
                state.activeTemplate = template
                state.toolbar.openPanel = nil
                return .none

            case .toolbar(.templateSelected(let template)):
                // Toolbar's forwarded action; promote to the
                // notebook-level template change above.
                return .send(.templateSelected(template))

            case .toolbar:
                return .none
            }
        }
    }

    // MARK: - Effects

    private func refresh(notebookID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let pages = try await notebookClient.fetchPagesForNotebook(notebookID)
                await send(.pagesLoaded(pages))
            } catch {
                log.error("Notebook refresh failed: \(error.localizedDescription)")
            }
        }
        .cancellable(id: "notebookRefresh-\(notebookID.uuidString)", cancelInFlight: true)
    }

    private func observeStoreChanges() -> Effect<Action> {
        .run { send in
            for await _ in ModelStoreObserver.observe() {
                await send(.storeDidChange)
            }
        }
        .cancellable(id: "notebookStoreObservation", cancelInFlight: true)
    }

    private func seedFirstPage(notebookID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let snap = try await notebookClient.createPage(notebookID, "blank")
                await send(.pageCreated(snap))
            } catch {
                log.error("First-page seed failed: \(error.localizedDescription)")
            }
        }
    }
}
