import ComposableArchitecture
import Foundation

/// Reusable library-search state machine. Owns the query, the debounce
/// timer, in-flight cancellation, and the result list. Consumers scope
/// this under their feature and intercept `.delegate(.resultSelected)`
/// to decide what "selected" means in their context — open vs. pick vs.
/// insert-as-link.
///
/// **Not browse-specific:** the reducer makes no assumption about the
/// presentation chrome around it. `LibraryBrowseView` wraps it with a
/// title bar + dismiss; a future picker variant wraps it differently;
/// a quick-switcher wraps it as an overlay. Same reducer, same view —
/// the wrappers change.
///
struct LibrarySearchFeature: Reducer {

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        /// Latest query text. The view binds to this via the
        /// wiring-view-supplied closure.
        var query: String = ""
        /// What kinds of items the consumer wants in results. Set once
        /// at presentation time — never mutated by the reducer.
        var scope: LibrarySearchScope = .all
        /// Resolved hits. Replaced wholesale on every settled query
        /// (debounce-driven). Empty for "no query + empty library" AND
        /// for "non-empty query with zero matches" — the view decides
        /// the message via `query.isEmpty`.
        var results: [LibrarySearchResult] = []
        /// True between query change and result arrival. Drives the
        /// optional progress affordance. Cleared by `resultsLoaded`.
        var isSearching: Bool = false
        /// Flips true on first `appeared` so the empty-state copy
        /// distinguishes "results not loaded yet" from "results
        /// genuinely empty."
        var hasLoadedOnce: Bool = false
    }

    // MARK: - Action

    @CasePathable
    enum Action: Equatable {
        case appeared
        case queryChanged(String)
        case resultsLoaded([LibrarySearchResult])
        case resultTapped(LibrarySearchResult.ID)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// Emitted when the user taps a result. Consumer decides
            /// whether to open it, select it back to a parent picker,
            /// pre-fill an integration target, etc.
            case resultSelected(LibrarySearchResult)
        }
    }

    // MARK: - Dependencies

    @Dependency(\.librarySearchService) var searchService
    /// Used to debounce keystrokes so each character doesn't fire its
    /// own service query. 250ms matches Apple's Spotlight cadence —
    /// fast enough to feel responsive, slow enough to coalesce typing.
    @Dependency(\.continuousClock) var clock

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                // First-load: kick off an empty-query search to
                // populate the "browse all" view. Consumers that
                // don't want this (a picker that should stay empty
                // until typed into) can override by not dispatching
                // `.appeared`.
                state.isSearching = true
                return runSearch(query: state.query, scope: state.scope)

            case .queryChanged(let query):
                state.query = query
                state.isSearching = true
                // Debounced re-search. Cancel-in-flight collapses
                // bursts of keystrokes to a single executed search.
                return .run { [scope = state.scope, query] send in
                    try? await clock.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    let results = (try? await searchService.search(query, scope)) ?? []
                    await send(.resultsLoaded(results))
                }
                .cancellable(id: "librarySearchExecute", cancelInFlight: true)

            case .resultsLoaded(let results):
                state.results = results
                state.isSearching = false
                state.hasLoadedOnce = true
                return .none

            case .resultTapped(let id):
                guard let result = state.results.first(where: { $0.id == id }) else {
                    return .none
                }
                return .send(.delegate(.resultSelected(result)))

            case .delegate:
                return .none
            }
        }
    }

    /// Immediate (no debounce) search — used by `.appeared` to
    /// populate the initial result set. The debounced path lives
    /// inline in `.queryChanged` because the sleep + cancellation
    /// orchestration is the whole point there.
    private func runSearch(query: String, scope: LibrarySearchScope) -> Effect<Action> {
        .run { send in
            let results = (try? await searchService.search(query, scope)) ?? []
            await send(.resultsLoaded(results))
        }
        .cancellable(id: "librarySearchExecute", cancelInFlight: true)
    }
}
