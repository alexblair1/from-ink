import ComposableArchitecture

struct AppFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var bootstrap: BootstrapFeature.State = .init()
        var home: HomeFeature.State?
    }

    @CasePathable
    enum Action {
        case bootstrap(BootstrapFeature.Action)
        case home(HomeFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.bootstrap, action: \.bootstrap) {
            BootstrapFeature()
        }

        Reduce { state, action in
            switch action {
            case .bootstrap(.delegate(.bootCompleted(let brief, _))):
                var homeState = HomeFeature.State()
                if let brief {
                    homeState.briefState = .loaded(brief)
                }
                state.home = homeState
                return .none

            case .bootstrap(.delegate(.bootFailed)):
                return .none

            case .bootstrap:
                return .none

            case .home:
                return .none
            }
        }
        .ifLet(\.home, action: \.home) {
            HomeFeature()
        }
    }
}
