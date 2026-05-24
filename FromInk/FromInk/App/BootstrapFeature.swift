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
        var _seededBrief: DailyBriefSnapshot?

        enum Phase: Equatable {
            case launching
            case ready
            case failed
        }
    }

    enum Stage: String, CaseIterable, Equatable, Hashable {
        case storage
        case authRestore
        case eventKitPermission
        case foundationModelsWarmup
        case briefSeed
    }

    enum Degradation: Equatable, Hashable {
        case calendarPermissionDenied
        case remindersPermissionDenied
        case foundationModelsUnavailable
        case briefSeedSkipped(reason: String)
        case authNotRestored
    }

    enum Action: Equatable {
        case start
        case stageStarted(Stage)
        case stageCompleted(Stage, [Degradation])
        case stageFailedRequired(Stage, BootstrapError)
        case briefSeeded(DailyBriefSnapshot)
        case retry
        case delegate(Delegate)

        enum Delegate: Equatable {
            case bootCompleted(
                brief: DailyBriefSnapshot?,
                degradations: Set<Degradation>
            )
            case bootFailed(BootstrapError)
        }
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

                // Ready only when ALL stages have completed — gating on
                // `briefSeed` alone is racy because `briefSeed` is fired
                // after `[authRestore, eventKitPermission, fmWarmup]`
                // complete, but those run in parallel. If `briefSeed`
                // happens to resolve before a still-in-flight `authRestore`
                // (e.g., FM cache hit + slow keychain sweep), declaring
                // ready early causes `bootCompleted` to fire twice with
                // different degradation sets.
                let allDone = Stage.allCases.allSatisfy(state.completedStages.contains)
                if allDone {
                    state.phase = .ready
                    state.currentStage = nil
                    return .merge(
                        effect,
                        .send(.delegate(.bootCompleted(
                            brief: state._seededBrief,
                            degradations: state.degradations
                        )))
                    )
                }

                return effect

            case .briefSeeded(let snapshot):
                state._seededBrief = snapshot
                return .none

            case .stageFailedRequired(_, let error):
                state.phase = .failed
                state.currentStage = nil
                state.error = error
                return .send(.delegate(.bootFailed(error)))

            case .retry:
                state.phase = .launching
                state.error = nil
                state._seededBrief = nil
                state.completedStages.removeAll()
                state.degradations.removeAll()
                state.currentStage = .storage
                return runStorage()

            case .delegate:
                return .none
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
                runAuthRestore(),
                runEventKitPermission(),
                runFoundationModelsWarmup()
            )

        case .authRestore, .eventKitPermission, .foundationModelsWarmup:
            let deps: Set<Stage> = [.authRestore, .eventKitPermission, .foundationModelsWarmup]
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
            @Dependency(\.syncedModelContext) var synced
            @Dependency(\.localModelContext) var local
            await send(.stageStarted(.storage))
            do {
                try await synced.warmup()
                try await local.warmup()
                await send(.stageCompleted(.storage, []))
            } catch {
                await send(.stageFailedRequired(.storage, .storageUnavailable(error)))
            }
        }
    }

    private func runAuthRestore() -> Effect<Action> {
        .run { send in
            @Dependency(\.keychainService) var keychain
            @Dependency(\.oauthService) var oauth
            @Dependency(\.backgroundTokenRefresh) var bgRefresh
            await send(.stageStarted(.authRestore))
            var degradations: [Degradation] = []
            do {
                let accounts = try keychain.allAccounts()
                if accounts.isEmpty {
                    await send(.stageCompleted(.authRestore, []))
                    return
                }
                // Sweep tokens expiring within 1 hour. Failures here
                // (network unreachable mid-sweep) degrade auth but
                // don't fail the stage — refresh will retry on next
                // foreground via the background task scheduler.
                await oauth.sweepExpiring(3600)
                // Schedule recurring background refresh for Slack's 30-day
                // token. Wrapped because `scheduleNext` can fail if the
                // BGTaskScheduler is unavailable (e.g., extension context).
                bgRefresh.scheduleNext()
                await send(.stageCompleted(.authRestore, degradations))
            } catch {
                degradations.append(.authNotRestored)
                await send(.stageCompleted(.authRestore, degradations))
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

