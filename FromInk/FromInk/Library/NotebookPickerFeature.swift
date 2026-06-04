import ComposableArchitecture
import Foundation

/// Two-phase picker for "select a notebook, then select a page within it."
/// Built as a reusable child feature — the parent (action sheet,
/// integrations row, future View All) presents it as a branded overlay,
/// listens for `.delegate(.selected(...))`, and acts on the result.
///
/// **Phases:**
///   1. `.notebookSelection` — search + grid of notebooks.
///   2. `.pageSelection(notebookID:notebookTitle:)` — two presets
///      ("Last edited" / "New page") plus a collapsed "More…" disclosure
///      that expands a thumbnail grid of every page in the notebook.
///
/// **Why phase enum, not nested features:** the two screens share the
/// same dismiss/back chrome and the same delegate-out path. A nested
/// `NotebookPageSelectionFeature` would duplicate that wiring without
/// reusing more than two delegate actions. One reducer keeps the state
/// transitions and the chrome under a single body.
///
/// **No link creation.** The picker doesn't know about
/// `CalendarItemLink` — it only emits a `(notebookID, page)` tuple.
/// Reusable across "link a calendar event," "move a dispatched task
/// here," and future flows that need to point at a specific page.
///
struct NotebookPickerFeature: Reducer {

    // MARK: - Phase

    enum Phase: Equatable {
        case notebookSelection
        /// Held flat (rather than inside an associated `pageSelection`
        /// payload struct) so it can be tweaked from the reducer without
        /// destructuring + re-wrapping. `notebookTitle` is denormalized
        /// off the picked snapshot so the header bar can render the
        /// notebook name without re-fetching.
        case pageSelection(notebookID: UUID, notebookTitle: String)
    }

    // MARK: - Selection result

    /// What the user chose as the destination page within the notebook.
    /// Caller resolves `.lastEdited` to whichever page the user touched
    /// most recently at navigation time, and `.new` to a freshly
    /// inserted page. Storing the resolution semantically at the picker
    /// level (rather than a `UUID?` with implicit meaning) keeps the
    /// downstream branches explicit.
    enum SelectedPage: Equatable {
        case lastEdited
        case new
        case existing(pageID: UUID)
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .notebookSelection
        var searchText: String = ""
        /// All notebooks the user owns. Refreshed on `.appeared`. The
        /// view filters this through `searchText` at render time —
        /// state stays a flat list to avoid recomputing snapshots on
        /// every keystroke.
        var notebooks: [NotebookSnapshot] = []
        /// Pages of the notebook the user advanced into. Empty until
        /// `.pageSelection` is entered.
        var pages: [NotePageSnapshot] = []
        /// `true` once the user taps the "More…" disclosure in the
        /// page-selection phase. Defaults to `false` so the picker
        /// stays compact (two preset rows, no grid) until invited to
        /// expand.
        var showsPageThumbnails: Bool = false
        /// `true` while a fetch is in flight. The view renders a
        /// placeholder so the user knows work is happening — important
        /// for first-launch when the notebook fetch may take a frame.
        var isLoading: Bool = false
    }

    // MARK: - Action

    @CasePathable
    enum Action: Equatable {
        case appeared
        case searchTextChanged(String)
        case notebooksLoaded([NotebookSnapshot])
        case notebookTapped(UUID)
        case pagesLoaded([NotePageSnapshot])
        case lastEditedPageTapped
        case newPageTapped
        case morePagesTapped
        case pageThumbnailTapped(UUID)
        case backTapped
        case dismissTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// User confirmed a destination. Parent creates the link
            /// (or whatever it does with the selection) and tears the
            /// presentation down.
            case selected(notebookID: UUID, page: SelectedPage)
            /// User tapped the X or the scrim. Parent dismisses.
            case dismissed
        }
    }

    // MARK: - Dependencies

    @Dependency(\.notebookClient) var notebookClient

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                state.isLoading = true
                return .run { send in
                    let notebooks = (try? await notebookClient.fetchAllNotebooks()) ?? []
                    await send(.notebooksLoaded(notebooks))
                }

            case .searchTextChanged(let text):
                state.searchText = text
                return .none

            case .notebooksLoaded(let notebooks):
                state.notebooks = notebooks
                state.isLoading = false
                return .none

            case .notebookTapped(let notebookID):
                // Resolve title from the loaded snapshots. The picker
                // is closed if the snapshot list doesn't contain the
                // tapped ID — which can't happen via the UI but might
                // via a programmatic .send during tests.
                guard let snapshot = state.notebooks.first(where: { $0.id == notebookID }) else {
                    return .none
                }
                state.phase = .pageSelection(
                    notebookID: notebookID,
                    notebookTitle: snapshot.title
                )
                state.showsPageThumbnails = false
                state.isLoading = true
                return .run { send in
                    let pages = (try? await notebookClient.fetchPagesForNotebook(notebookID)) ?? []
                    await send(.pagesLoaded(pages))
                }

            case .pagesLoaded(let pages):
                state.pages = pages.sorted { $0.index < $1.index }
                state.isLoading = false
                return .none

            case .lastEditedPageTapped:
                guard case .pageSelection(let notebookID, _) = state.phase else { return .none }
                return .send(.delegate(.selected(notebookID: notebookID, page: .lastEdited)))

            case .newPageTapped:
                guard case .pageSelection(let notebookID, _) = state.phase else { return .none }
                return .send(.delegate(.selected(notebookID: notebookID, page: .new)))

            case .morePagesTapped:
                state.showsPageThumbnails.toggle()
                return .none

            case .pageThumbnailTapped(let pageID):
                guard case .pageSelection(let notebookID, _) = state.phase else { return .none }
                return .send(.delegate(.selected(notebookID: notebookID, page: .existing(pageID: pageID))))

            case .backTapped:
                // Only meaningful in pageSelection. Clears the loaded
                // pages so a subsequent re-enter pulls fresh data
                // (cheap fetch, and avoids showing stale thumbnails
                // if the user has edited the notebook elsewhere).
                state.phase = .notebookSelection
                state.pages = []
                state.showsPageThumbnails = false
                return .none

            case .dismissTapped:
                return .send(.delegate(.dismissed))

            case .delegate:
                return .none
            }
        }
    }
}
