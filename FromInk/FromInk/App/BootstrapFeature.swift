import ComposableArchitecture
import EventKit
import Foundation

struct BootstrapFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .launching
        var currentStage: Stage?
        var completedStages: Set<Stage> = []
        var degradations: Set<Degradation> = []
        var error: BootstrapError?
        var seededBrief: DailyBriefSnapshot?

        enum Phase: Equatable {
            case launching
            case ready
            case failed
        }
    }

    enum Stage: String, CaseIterable, Equatable, Hashable {
        case storage
        case eventKitPermission
        case foundationModelsWarmup
        case briefSeed
    }

    enum Degradation: Equatable, Hashable {
        case calendarPermissionDenied
        case remindersPermissionDenied
        case foundationModelsUnavailable
        case briefSeedSkipped(reason: String)
    }

    enum Action: Equatable {
        case start
        case stageStarted(Stage)
        case stageCompleted(Stage, [Degradation])
        case stageFailedRequired(Stage, BootstrapError)
        case briefSeeded(DailyBriefSnapshot)
        case retry
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .start:
                state.phase = .launching
                state.currentStage = .storage
                return runStorage()

            case .stageStarted(let stage):
                state.currentStage = stage
                return .none

            case .stageCompleted(let stage, let degradations):
                state.completedStages.insert(stage)
                state.degradations.formUnion(degradations)

                let effect = nextStage(after: stage, state: state)

                // briefSeed is the terminal stage — transition to ready.
                if state.completedStages.contains(.briefSeed) {
                    state.phase = .ready
                    state.currentStage = nil
                }

                return effect

            case .briefSeeded(let snapshot):
                state.seededBrief = snapshot
                return .none

            case .stageFailedRequired(_, let error):
                state.phase = .failed
                state.currentStage = nil
                state.error = error
                return .none

            case .retry:
                state.phase = .launching
                state.error = nil
                state.completedStages.removeAll()
                state.degradations.removeAll()
                state.currentStage = .storage
                return runStorage()
            }
        }
    }

    // MARK: - DAG
    //
    // The only place the stage ordering lives. Adding a stage means
    // adding one case here plus one runner.

    private func nextStage(
        after stage: Stage,
        state: State
    ) -> Effect<Action> {
        switch stage {
        case .storage:
            return .merge(
                runEventKitPermission(),
                runFoundationModelsWarmup()
            )

        case .eventKitPermission, .foundationModelsWarmup:
            let deps: Set<Stage> = [.eventKitPermission, .foundationModelsWarmup]
            return deps.isSubset(of: state.completedStages)
                ? runBriefSeed()
                : .none

        case .briefSeed:
            return .none
        }
    }

    // MARK: - Effect runners

    private func runStorage() -> Effect<Action> {
        .run { send in
            @Dependency(\.syncedModelContext) var ctx
            await send(.stageStarted(.storage))
            do {
                try await ctx.warmup()
                await send(.stageCompleted(.storage, []))
            } catch {
                await send(.stageFailedRequired(.storage, .storageUnavailable(error)))
            }
        }
    }

    private func runEventKitPermission() -> Effect<Action> {
        .run { send in
            await send(.stageStarted(.eventKitPermission))
            var degradations: [Degradation] = []
            let calendarStatus = EKEventStore.authorizationStatus(for: .event)
            let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            if calendarStatus == .denied || calendarStatus == .restricted {
                degradations.append(.calendarPermissionDenied)
            }
            if reminderStatus == .denied || reminderStatus == .restricted {
                degradations.append(.remindersPermissionDenied)
            }
            await send(.stageCompleted(.eventKitPermission, degradations))
        }
    }

    private func runFoundationModelsWarmup() -> Effect<Action> {
        .run { send in
            @Dependency(\.foundationModelsService) var fm
            await send(.stageStarted(.foundationModelsWarmup))
            let available = fm.isAvailable()
            let degradations: [Degradation] =
                available ? [] : [.foundationModelsUnavailable]
            await send(.stageCompleted(.foundationModelsWarmup, degradations))
        }
    }

    private func runBriefSeed() -> Effect<Action> {
        .run { send in
            @Dependency(\.dailyBriefClient) var client
            await send(.stageStarted(.briefSeed))
            do {
                let snapshot = try await client.fetchOrGenerate()
                await send(.briefSeeded(snapshot))
                await send(.stageCompleted(.briefSeed, []))
            } catch {
                await send(.stageCompleted(
                    .briefSeed,
                    [.briefSeedSkipped(reason: String(describing: error))]
                ))
            }
        }
    }
}
