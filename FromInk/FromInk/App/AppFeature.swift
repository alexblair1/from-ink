import ComposableArchitecture

struct AppFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var bootstrap: BootstrapFeature.State = .init()
        var onboarding: OnboardingFeature.State?
        var home: HomeFeature.State?
        /// Brief loaded by bootstrap, parked here while the user moves
        /// through onboarding so home can still seed with it on completion.
        /// `nil` if bootstrap couldn't seed a brief.
        var pendingBrief: DailyBriefSnapshot?
    }

    @CasePathable
    enum Action {
        case bootstrap(BootstrapFeature.Action)
        case onboarding(OnboardingFeature.Action)
        case home(HomeFeature.Action)
        /// Resolution of `loadHasSeenOnboarding` and `loadOnboardingStep`
        /// after bootstrap completes. The optional step is the user's
        /// in-progress position from a prior session — non-nil only when
        /// onboarding was interrupted (e.g. iOS terminated the app while
        /// the user was in the system Settings app).
        case onboardingStateResolved(hasSeen: Bool, savedStep: OnboardingStep?)
    }

    @Dependency(\.oauthService) var oauthService
    @Dependency(\.calendarItemLinkValidator) var calendarItemLinkValidator
    @Dependency(\.userPreferences) var userPreferences

    var body: some Reducer<State, Action> {
        Scope(state: \.bootstrap, action: \.bootstrap) {
            BootstrapFeature()
        }

        Reduce { state, action in
            switch action {
            case .bootstrap(.delegate(.bootCompleted(let brief, _))):
                state.pendingBrief = brief
                // Long-lived background subscription that reconciles
                // `CalendarItemLink` records against EventKit on every
                // calendar-change notification. Drains forever; the
                // cancellable ID ensures `cancelInFlight: true` would
                // tear down a duplicate if `bootCompleted` ever fired
                // twice (it shouldn't, but defense-in-depth).
                let reconcile = Effect<Action>.run { _ in
                    await calendarItemLinkValidator.observeAndReconcile()
                }
                .cancellable(id: "calendarItemLinkValidator", cancelInFlight: true)

                let resolveOnboarding = Effect<Action>.run { send in
                    let hasSeen = await userPreferences.loadHasSeenOnboarding()
                    let savedStep = await userPreferences.loadOnboardingStep()
                    await send(.onboardingStateResolved(hasSeen: hasSeen, savedStep: savedStep))
                }

                return .merge(reconcile, resolveOnboarding)

            case .onboardingStateResolved(hasSeen: true, _):
                state.home = makeHomeState(brief: state.pendingBrief)
                state.pendingBrief = nil
                return .none

            case .onboardingStateResolved(hasSeen: false, let savedStep):
                // Resume on the saved step if the user was mid-flow when
                // the app was terminated (most commonly from the system
                // killing the app while the user was in Settings after
                // tapping "Open Settings" from the permissions screen).
                var onboardingState = OnboardingFeature.State()
                if let savedStep {
                    onboardingState.step = savedStep
                }
                state.onboarding = onboardingState
                return .none

            case .bootstrap(.delegate(.bootFailed)):
                return .none

            case .bootstrap:
                return .none

            case .onboarding(.delegate(.completed)):
                state.onboarding = nil
                state.home = makeHomeState(brief: state.pendingBrief)
                state.pendingBrief = nil
                return .none

            case .onboarding:
                return .none

            case .home(.foregrounded):
                return .run { _ in
                    await oauthService.sweepExpiring(3600)
                }

            case .home:
                return .none
            }
        }
        .ifLet(\.onboarding, action: \.onboarding) {
            OnboardingFeature()
        }
        .ifLet(\.home, action: \.home) {
            HomeFeature()
        }
    }

    private func makeHomeState(brief: DailyBriefSnapshot?) -> HomeFeature.State {
        var homeState = HomeFeature.State()
        if let brief {
            homeState.briefState = .loaded(brief)
        } else {
            // Don't leave `briefState` at the default `.loading` when we
            // have no seeded brief. For no-permissions users (a real
            // first-run case — they decline calendar/reminders, so a
            // brief can never be generated), the loading UI would flash
            // until `HomeFeature.appeared` fires `loadBrief`, which
            // eventually resolves to `.empty`. That `.loading → .empty`
            // transition reads as a failed fetch.
            //
            // Starting at `.empty` skips the flash. Granted-permissions
            // users still see `.empty → .loaded` when the brief arrives,
            // which reads as content arriving (correct affordance).
            homeState.briefState = .empty
        }
        return homeState
    }
}
