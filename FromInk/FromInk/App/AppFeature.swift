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

    @Dependency(\.oauthService) var oauthService
    @Dependency(\.calendarItemLinkValidator) var calendarItemLinkValidator

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
                // Long-lived background subscription that reconciles
                // `CalendarItemLink` records against EventKit on every
                // calendar-change notification. Drains forever; the
                // cancellable ID ensures `cancelInFlight: true` would
                // tear down a duplicate if `bootCompleted` ever fired
                // twice (it shouldn't, but defense-in-depth).
                return .run { _ in
                    await calendarItemLinkValidator.observeAndReconcile()
                }
                .cancellable(id: "calendarItemLinkValidator", cancelInFlight: true)

            case .bootstrap(.delegate(.bootFailed)):
                return .none

            case .bootstrap:
                return .none

            case .home(.foregrounded):
                return .run { _ in
                    await oauthService.sweepExpiring(3600)
                }

            case .home:
                return .none
            }
        }
        .ifLet(\.home, action: \.home) {
            HomeFeature()
        }
    }
}
