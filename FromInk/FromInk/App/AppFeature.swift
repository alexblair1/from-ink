import ComposableArchitecture

struct AppFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var bootstrap: BootstrapFeature.State = .init()
    }

    @CasePathable
    enum Action {
        case bootstrap(BootstrapFeature.Action)
        case calendarChanged
        case briefRefreshed(DailyBriefSnapshot)
    }

    @Dependency(\.dailyBriefClient) var dailyBriefClient

    var body: some Reducer<State, Action> {
        Scope(state: \.bootstrap, action: \.bootstrap) {
            BootstrapFeature()
        }

        Reduce { state, action in
            switch action {
            case .bootstrap(.stageCompleted(.briefSeed, _)):
                return .run { send in
                    for await _ in dailyBriefClient.calendarChanges() {
                        await send(.calendarChanged)
                    }
                }
                .cancellable(id: "calendarObservation")

            case .calendarChanged:
                return .run { send in
                    do {
                        let snapshot = try await dailyBriefClient.fetchOrGenerate()
                        await send(.briefRefreshed(snapshot))
                    } catch {}
                }

            case .briefRefreshed(let snapshot):
                state.bootstrap.seededBrief = snapshot
                return .none

            case .bootstrap:
                return .none
            }
        }
    }

}
