# EDD — Application Bootstrap: Composition Root + BootstrapFeature

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-13 |
| Implements ticket | F-12 (App bootstrap state machine) |
| Companion docs | EDD — Data Layer · EDD — PKCE · EDD — View Layer |

---

## Table of contents

1. [Summary](#1-summary)
2. [Goals & non-goals](#2-goals--non-goals)
3. [Core philosophy](#3-core-philosophy)
4. [The two registries](#4-the-two-registries)
5. [AppDependencyContainer — the composition root](#5-appdependencycontainer--the-composition-root)
6. [BootstrapFeature — the state machine](#6-bootstrapfeature--the-state-machine)
7. [Stages and the dependency DAG](#7-stages-and-the-dependency-dag)
8. [Failure model](#8-failure-model)
9. [Launch UI integration](#9-launch-ui-integration)
10. [App entry point](#10-app-entry-point)
11. [Testing strategy](#11-testing-strategy)
12. [Migration plan](#12-migration-plan)
13. [Anti-patterns](#13-anti-patterns)
14. [Open questions](#14-open-questions)
15. [Decision log](#15-decision-log)

---

## 1. Summary

From Ink wires its live dependencies through a single composition root (`AppDependencyContainer`) and orchestrates the boot sequence through a TCA reducer (`BootstrapFeature`). The container is **how** dependencies are constructed; the reducer is **when** they run and **what happens if they fail**.

Today, bootstrap is implicit and split across `FromInkApp.init()` (force-tries a `ModelContainer`), a free-function `configure(with:)` call on `SyncedModelContextDependency`, and a `.task` modifier on `ContentView` that fires off `DailyBriefClient.fetchOrGenerate`. This EDD replaces that arrangement with an explicit two-phase pattern: a composition root that owns construction, and a reducer that owns the state machine.

The composition root uses `private(set) lazy var` properties to form an implicit DAG, late-instantiated on first access. The container is consumed once during `prepareDependencies { ... }` at app launch, and after that all access goes through `@Dependency`.

---

## 2. Goals & non-goals

### Goals

- Make every bootstrap failure surface explicitly — never crash silently via `try!`.
- Distinguish **required** boot stages (storage, auth restore) from **optional** ones (Foundation Models warmup, brief seed, EventKit permission probe).
- Allow degraded-ready states — the app can boot to functional with permissions denied or networks unreachable.
- Keep the launch UI a thin projection of `BootstrapFeature.State` — no parallel timers, no `DispatchQueue.asyncAfter`, no `Task.sleep` placeholder delays.
- Make the boot sequence testable with `TestStore` like any other reducer.
- Keep TCA `@Dependency` as the only access pattern after launch — the container is invisible to reducers and views.

### Non-goals

- This EDD does **not** specify individual dependency clients (`OCRService`, `FoundationModelsService`, etc.) — those follow the pattern in CLAUDE.md and the PKCE EDD.
- This EDD does **not** define the SwiftData schema — see the data model EDD.
- This EDD does **not** cover URL deep linking or push notification routing on cold start — that's a follow-up (F-15, Navigation EDD).
- This EDD does **not** specify Mac vs iOS bootstrap divergence — both platforms use the same reducer; platform-specific stages are gated by `#if`.

---

## 3. Core philosophy

Three principles govern bootstrap design:

1. **Construction is separate from orchestration.** The composition root knows *how* to build a `ModelContainer`; the reducer decides *whether to retry*, *what to surface*, and *what comes next*. Mixing the two is what produces the `try!` pattern.
2. **Every boot step has a known failure mode.** A boot step is either required, optional-but-observable (degrades the experience), or background (never blocks ready). Steps that don't fit one of these are not boot steps — they belong in a feature reducer.
3. **The launch screen renders state, not time.** No artificial delays, no minimum-display timers. The launch screen disappears the instant `BootstrapFeature.State.phase` transitions to `.ready` (or `.failed`).

A fourth principle is implicit: **the composition root is touched exactly once**. Reducers never reach into it. Once `prepareDependencies` hands its lazy resolutions to TCA, the container is dormant.

---

## 4. The two registries

From Ink has two parallel registries of live values, and they serve different purposes:

| | `AppDependencyContainer` | `DependencyValues` (TCA) |
|---|---|---|
| Role | Composition root | Lookup registry |
| Mutability | Set once, at launch | Replaced per-test via `withDependencies` |
| Who reads it | `FromInkApp` only | Every reducer, every wiring view |
| Lifetime | Process lifetime | Per-reducer scope |
| Failure surface | Explicit (`try`) | None — values resolved already |
| Test substitution | Build a `.test()` container | `withDependencies { ... }` |

The container exists because some live values need **runtime-configured construction** — the SwiftData `ModelContainer`, the OAuth access-token closure, the Supabase client (if added later), the file URLs for caches. These cannot be expressed as static `liveValue` properties because they depend on assets, file paths, or other live values constructed earlier in the boot sequence.

The TCA registry exists because reducers must not know about construction order. By the time any reducer runs, every `@Dependency(\.x)` resolves to the value the container produced.

### The handoff

```swift
@main
struct FromInkApp: App {
    private let container = AppDependencyContainer.live()

    var body: some Scene {
        WindowGroup {
            AppRootView(store: makeRootStore())
        }
    }

    private func makeRootStore() -> StoreOf<AppFeature> {
        Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: { deps in
            container.install(into: &deps)
        }
    }
}
```

`container.install(into:)` is the only seam between the two registries.

---

## 5. AppDependencyContainer — the composition root

### 5.1 Shape

```swift
import ComposableArchitecture
import SwiftData
import Foundation
import os

/// Composition root. Constructs live dependencies once, in order, and installs
/// them into the TCA registry at app launch. Never read after `install(into:)`.
///
final class AppDependencyContainer {

    private let log = Logger(subsystem: "com.fromink.app", category: "Bootstrap")

    // MARK: - Foundational

    private(set) lazy var errorLogger: ErrorLogger = .live

    private(set) lazy var keychain: KeychainService = .live(logger: errorLogger)

    private(set) lazy var userPreferences: UserPreferences = .live

    // MARK: - Storage

    private(set) lazy var modelContainer: Result<ModelContainer, BootstrapError> = {
        do {
            let container = try ModelContainer(
                for: Notebook.self, NotePage.self, Folder.self,
                    Tag.self, RoutedItem.self, DailyBriefRecord.self,
                    NoteHistoryEntry.self
            )
            return .success(container)
        } catch {
            log.error("ModelContainer init failed: \(error)")
            errorLogger.log(.bootstrapStorageFailed, error: error)
            return .failure(.storageUnavailable(error))
        }
    }()

    private(set) lazy var syncedModelContext: SyncedModelContextDependency = {
        switch modelContainer {
        case .success(let container):
            return .live(container: container)
        case .failure:
            return .unavailable  // returns .empty snapshots, no-ops on save
        }
    }()

    // MARK: - ML

    private(set) lazy var ocrService: OCRService = .live
    private(set) lazy var foundationModelsService: FoundationModelsService = .live
    private(set) lazy var eventKitService: EventKitService = .live
    private(set) lazy var weatherService: WeatherService = .live(logger: errorLogger)
    private(set) lazy var locationService: LocationService = .live

    // MARK: - Auth

    private(set) lazy var oauthService: OAuthService = {
        OAuthService.live(keychain: keychain, errorLogger: errorLogger)
    }()

    // MARK: - Composite

    private(set) lazy var dailyBriefClient: DailyBriefClient = {
        DailyBriefClient.live(
            modelContext: syncedModelContext,
            eventKit: eventKitService,
            foundationModels: foundationModelsService,
            errorLogger: errorLogger
        )
    }()

    // MARK: - Factories

    static func live() -> AppDependencyContainer { AppDependencyContainer() }
    static func test() -> AppDependencyContainer { /* see §11 */ }
}

// MARK: - Installation

extension AppDependencyContainer {
    func install(into deps: inout DependencyValues) {
        deps.errorLogger = errorLogger
        deps.keychainService = keychain
        deps.userPreferences = userPreferences
        deps.syncedModelContext = syncedModelContext
        deps.ocrService = ocrService
        deps.foundationModelsService = foundationModelsService
        deps.eventKitService = eventKitService
        deps.weatherService = weatherService
        deps.locationService = locationService
        deps.oauthService = oauthService
        deps.dailyBriefClient = dailyBriefClient
    }
}
```

### 5.2 Rules

- **One `private(set) lazy var` per dependency.** Late instantiation is the mechanism. Ordering emerges from access, not from a manual `setUp()` method.
- **Storage failures are Result-typed, not crashes.** `modelContainer: Result<ModelContainer, BootstrapError>`. Downstream lazies branch on the result and fall back to no-op clients when storage is unavailable.
- **The container never throws from a property.** Throwing accessors couple the construction graph to the call site. Wrap failures as `Result` or as a `.unavailable` variant of the dependency.
- **No reducer reads the container.** `install(into:)` is the only public mutation surface.
- **Composite clients receive their inputs, never the container.** `DailyBriefClient.live(modelContext:eventKit:foundationModels:)` — pass the resolved dependencies, not `self`.

### 5.3 Why not just initialize everything in `FromInkApp.init`?

Because the resulting `init` becomes a 100-line block where ordering is implicit in line number. Adding a dependency requires reading the whole init to find where it slots. The container makes the DAG observable via the lazies: if `dailyBriefClient` accesses `syncedModelContext` which accesses `modelContainer`, the order is encoded in the property body.

---

## 6. BootstrapFeature — the state machine

The container constructs live values lazily; the reducer **decides when to trigger that construction** and **how to react when it fails**. Without the reducer, every consumer must implement its own "what if the dep isn't ready yet" logic — exactly what produced the bug where `ContentView.task` races storage configuration.

### 6.1 State

```swift
struct BootstrapFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .launching
        var currentStage: Stage?
        var completedStages: Set<Stage> = []
        var degradations: Set<Degradation> = []
        var error: BootstrapError?

        enum Phase: Equatable {
            case launching
            case ready
            case failed
        }
    }

    enum Stage: String, CaseIterable, Equatable {
        case storage
        case authRestore
        case eventKitPermission
        case foundationModelsWarmup
        case briefSeed
        case featureFlags
    }

    enum Degradation: Equatable {
        case calendarPermissionDenied
        case remindersPermissionDenied
        case foundationModelsUnavailable
        case weatherUnavailable
        case briefSeedSkipped(reason: String)
        case authNotRestored  // user is signed out, not an error
    }

    // ... Action, body
}
```

`Stage` enumerates the discrete boot steps. `Degradation` enumerates the *known* ways a step can soft-fail without making the app unusable. `error` is set only when a required stage fails — the app cannot continue.

### 6.2 Actions

```swift
enum Action: Equatable {
    case start
    case stageStarted(Stage)
    case stageCompleted(Stage, [Degradation])  // empty array = clean success
    case stageFailedRequired(Stage, BootstrapError)
    case retry
    case proceedDegraded  // user dismissed an optional-failure banner
}
```

### 6.3 Body

```swift
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
            return nextStage(after: stage, state: state)

        case .stageFailedRequired(let stage, let error):
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

        case .proceedDegraded:
            state.phase = .ready
            return .none
        }
    }
}
```

`nextStage(after:state:)` is the only place the DAG is encoded — it returns the next `Effect` based on which stage just finished. Branching happens in **one** location, not scattered through the reducer.

### 6.4 The effect runners

```swift
private func runStorage() -> Effect<Action> {
    .run { send in
        @Dependency(\.syncedModelContext) var ctx
        // Touching `ctx.context()` forces the lazy container init.
        // If it's the .unavailable variant, every call returns an empty
        // in-memory context — the app boots, persistence is a no-op.
        await send(.stageStarted(.storage))
        do {
            _ = try await ctx.warmup()
            await send(.stageCompleted(.storage, []))
        } catch {
            await send(.stageFailedRequired(.storage, .storageUnavailable(error)))
        }
    }
}

private func runEventKitPermission() -> Effect<Action> {
    .run { send in
        @Dependency(\.eventKitService) var eventKit
        await send(.stageStarted(.eventKitPermission))
        let calendar = await eventKit.calendarAuthStatus()
        let reminders = await eventKit.remindersAuthStatus()
        var degradations: [BootstrapFeature.Degradation] = []
        if calendar == .denied { degradations.append(.calendarPermissionDenied) }
        if reminders == .denied { degradations.append(.remindersPermissionDenied) }
        await send(.stageCompleted(.eventKitPermission, degradations))
    }
}

private func runFoundationModelsWarmup() -> Effect<Action> {
    .run { send in
        @Dependency(\.foundationModelsService) var fm
        await send(.stageStarted(.foundationModelsWarmup))
        let available = await fm.isAvailable()
        let degradations: [BootstrapFeature.Degradation] =
            available ? [] : [.foundationModelsUnavailable]
        await send(.stageCompleted(.foundationModelsWarmup, degradations))
    }
}

private func runBriefSeed() -> Effect<Action> {
    .run { send in
        @Dependency(\.dailyBriefClient) var client
        await send(.stageStarted(.briefSeed))
        do {
            _ = try await client.fetchOrGenerate()
            await send(.stageCompleted(.briefSeed, []))
        } catch {
            await send(.stageCompleted(
                .briefSeed,
                [.briefSeedSkipped(reason: String(describing: error))]
            ))
        }
    }
}
```

Required stages fail loud (`stageFailedRequired`). Optional stages always complete — they signal trouble through the `degradations` array.

---

## 7. Stages and the dependency DAG

```
                     ┌──────────┐
                     │  start   │
                     └────┬─────┘
                          ▼
                     ┌──────────┐
                     │ storage  │  REQUIRED — fail-fast
                     └────┬─────┘
                          ▼
              ┌───────────┴─────────────┐
              ▼                         ▼
      ┌──────────────┐         ┌──────────────────┐
      │ authRestore  │         │ eventKit perm    │   parallel branch
      │  OPTIONAL    │         │ probe (optional) │
      └──────┬───────┘         └─────────┬────────┘
             │                           │
             │              ┌────────────┴────────────┐
             │              ▼                         ▼
             │     ┌────────────────┐       ┌──────────────────┐
             │     │ FM warmup      │       │ featureFlags     │
             │     │ (optional)     │       │ (optional)       │
             │     └────────┬───────┘       └──────────┬───────┘
             │              │                          │
             └──────────────┼──────────────────────────┘
                            ▼
                   ┌─────────────────┐
                   │  briefSeed      │  OPTIONAL — degrades only
                   └────────┬────────┘
                            ▼
                       ┌────────┐
                       │  ready │
                       └────────┘
```

### Stage table

| Stage | Required | Inputs | Surface if it fails |
|---|---|---|---|
| `storage` | ✅ | `modelContainer` | `phase = .failed`, retry UI |
| `authRestore` | ❌ | `keychain`, `oauthService` | `.authNotRestored` degradation; user lands on home in signed-out state |
| `eventKitPermission` | ❌ | `eventKitService` | `.calendarPermissionDenied` / `.remindersPermissionDenied` |
| `foundationModelsWarmup` | ❌ | `foundationModelsService` | `.foundationModelsUnavailable` (older device, language disabled) |
| `briefSeed` | ❌ | `dailyBriefClient` | `.briefSeedSkipped(reason:)` |
| `featureFlags` | ❌ | `featureFlagService` | logged, no degradation; flags fall back to defaults |

### Parallelism

The two branches after `storage` (auth restore and the eventKit/FM/featureFlags chain) are independent. The reducer issues them as a single `.merge(...)` effect; both branches complete via their own `.stageCompleted` actions; `briefSeed` only kicks off once both `foundationModelsWarmup` and `eventKitPermission` are in `completedStages`. The DAG check lives inside `nextStage(after:state:)`:

```swift
private func nextStage(after stage: Stage, state: State) -> Effect<Action> {
    switch stage {
    case .storage:
        return .merge(
            runAuthRestore(),
            runEventKitPermission()
        )
    case .eventKitPermission:
        return .merge(
            runFoundationModelsWarmup(),
            runFeatureFlags()
        )
    case .foundationModelsWarmup, .featureFlags:
        let deps: Set<Stage> = [.foundationModelsWarmup, .eventKitPermission]
        return deps.isSubset(of: state.completedStages)
            ? runBriefSeed()
            : .none
    case .authRestore:
        // not a gate for any later stage — boot completes when other branch finishes
        return state.completedStages.contains(.briefSeed)
            ? .send(.proceedDegraded)
            : .none
    case .briefSeed:
        return state.completedStages.contains(.authRestore)
            ? .send(.proceedDegraded)
            : .none
    }
}
```

This is the only place the DAG lives. Adding a new stage means adding one case here plus one runner — no edits scattered through the reducer body.

---

## 8. Failure model

Every boot step falls into exactly one of three buckets:

### 8.1 Required (fail-fast)

The app **cannot run** without this step. Currently only `storage` qualifies. On failure:

- `state.phase = .failed`
- Launch screen swaps to an error view with `Try again` (retries the reducer) and `Send report` (writes the failure to the `ErrorLogger` CloudKit public DB).
- No degraded mode — the user cannot proceed.

### 8.2 Optional-observable (degrades)

The app **can run** but a feature is impaired. Examples: calendar permission denied, Foundation Models unavailable, brief seed failed. On soft failure:

- The relevant `Degradation` is added to `state.degradations`.
- Boot continues.
- Affected features check `state.degradations` (passed through `AppFeature.State`) and render fallback UI — empty Daily Brief, "Grant calendar access" banner, etc.

### 8.3 Background (silent)

The app **can run** with no user-visible impact. Examples: feature flag fetch failure (defaults take over), telemetry handshake failure. Logged to `ErrorLogger`, otherwise invisible.

### 8.4 BootstrapError

```swift
enum BootstrapError: Equatable, Error {
    case storageUnavailable(any Error)
    case schemaMigrationFailed(any Error)

    static func == (lhs: BootstrapError, rhs: BootstrapError) -> Bool {
        switch (lhs, rhs) {
        case (.storageUnavailable, .storageUnavailable),
             (.schemaMigrationFailed, .schemaMigrationFailed):
            return true
        default: return false
        }
    }
}
```

Only required-stage failures need a typed error. Optional-stage soft failures are expressed as `Degradation` cases — the *consequence* is what matters, not the underlying `Error`.

---

## 9. Launch UI integration

The launch screen is a wiring view that reads `BootstrapFeature.State.phase`:

```swift
struct AppRootWiringView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        ZStack {
            switch store.bootstrap.phase {
            case .launching:
                LaunchScreen()
                    .transition(.opacity)
            case .ready:
                AppShellView(store: store.scope(state: \.shell, action: \.shell))
            case .failed:
                BootstrapFailureView(
                    error: store.bootstrap.error,
                    onRetry: { store.send(.bootstrap(.retry)) }
                )
                .transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.12), value: store.bootstrap.phase)
        .task { store.send(.bootstrap(.start)) }
    }
}
```

### Rules for launch UI

- **No artificial timers.** The launch screen disappears the instant `.phase` flips to `.ready`. If boot is fast, the screen flickers — that is correct.
- **No `DispatchQueue.asyncAfter` / `Task.sleep`.** Either you're waiting on a boot step (model it as a stage) or you're not (don't insert a delay).
- **Animation is `ds.animation.slow` (120ms linear).** Matches the design system rule; no spring.
- **The system launch screen (Info.plist) and the in-app launch screen must match visually.** If the system launch shows just a paper background, the in-app `LaunchScreen` must show the same paper background plus whatever wordmark / progress overlay it adds. There must be no jump at handoff.
- **Optional progress text** can be rendered from `state.currentStage` if boot ever runs long enough to matter (>500ms). Default to silent — a flashing stage label on a 200ms boot is noise.

---

## 10. App entry point

```swift
@main
struct FromInkApp: App {
    @AppStorage("appearanceSetting")
    private var appearance: AppearanceSetting = .system

    private let container: AppDependencyContainer
    private let store: StoreOf<AppFeature>

    init() {
        let container = AppDependencyContainer.live()
        self.container = container
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: { deps in
            container.install(into: &deps)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootWiringView(store: store)
                .designSystem(.standard)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container.modelContainerForSwiftUI)  // see below
    }
}
```

### 10.1 The `.modelContainer(_:)` modifier

SwiftUI's `@Query` property wrapper resolves its container via the `.modelContainer` modifier in the scene hierarchy. Reducers resolve it via `@Dependency(\.syncedModelContext)`. Both must point at the **same instance**.

The container exposes a SwiftUI-facing helper:

```swift
extension AppDependencyContainer {
    var modelContainerForSwiftUI: ModelContainer {
        switch modelContainer {
        case .success(let c): return c
        case .failure:
            // Fallback ephemeral container — schema-compatible, in-memory.
            // The app is in `.failed` phase anyway; views will not be visible.
            return try! ModelContainer(
                for: Notebook.self, NotePage.self, /* ... */,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
}
```

This is the **only** `try!` in the bootstrap path, and it's covered by a fallback that runs only when the user is already looking at `BootstrapFailureView`. If the in-memory container itself fails, the device is in a state where the app cannot run regardless.

---

## 11. Testing strategy

### 11.1 BootstrapFeature unit tests

Use `TestStore` like any other reducer. Each stage's `Effect` resolves through `@Dependency`, so substitution is via `withDependencies`.

```swift
func test_bootstrap_happyPath() async {
    let store = TestStore(initialState: BootstrapFeature.State()) {
        BootstrapFeature()
    } withDependencies: {
        $0.syncedModelContext = .preview
        $0.eventKitService.calendarAuthStatus = { .authorized }
        $0.eventKitService.remindersAuthStatus = { .authorized }
        $0.foundationModelsService.isAvailable = { true }
        $0.featureFlagService.refresh = { }
        $0.dailyBriefClient.fetchOrGenerate = { .empty }
        $0.oauthService.restoreSession = { .restored }
    }

    await store.send(.start) {
        $0.phase = .launching
        $0.currentStage = .storage
    }
    await store.receive(.stageStarted(.storage))
    await store.receive(.stageCompleted(.storage, [])) {
        $0.completedStages.insert(.storage)
    }
    // ... merged branches complete in order
    await store.receive(.proceedDegraded) {
        $0.phase = .ready
    }
}

func test_bootstrap_storageFailure_marksFailed() async {
    let store = TestStore(initialState: BootstrapFeature.State()) {
        BootstrapFeature()
    } withDependencies: {
        $0.syncedModelContext = .alwaysFails
    }

    await store.send(.start) { $0.currentStage = .storage }
    await store.receive(.stageStarted(.storage))
    await store.receive(.stageFailedRequired(.storage, .storageUnavailable(...))) {
        $0.phase = .failed
        $0.error = .storageUnavailable(...)
    }
}

func test_bootstrap_calendarDenied_addsDegradation() async {
    let store = TestStore(initialState: BootstrapFeature.State()) {
        BootstrapFeature()
    } withDependencies: {
        $0.eventKitService.calendarAuthStatus = { .denied }
        // ... other deps green
    }

    // walk to ready, assert degradation is present
    XCTAssertEqual(store.state.degradations, [.calendarPermissionDenied])
    XCTAssertEqual(store.state.phase, .ready)
}
```

### 11.2 Container tests

A `.test()` factory swaps each live builder with a deterministic stub:

```swift
extension AppDependencyContainer {
    static func test(
        modelContainer: Result<ModelContainer, BootstrapError> = .success(.inMemory),
        foundationModelsAvailable: Bool = true
    ) -> AppDependencyContainer {
        let c = AppDependencyContainer()
        c._modelContainer = modelContainer
        c._foundationModelsService = .testValue(isAvailable: foundationModelsAvailable)
        // ... etc
        return c
    }
}
```

Container tests verify the DAG: accessing `dailyBriefClient` triggers `syncedModelContext` triggers `modelContainer`. Use `XCTAssertEqual(callOrder, [.modelContainer, .syncedModelContext, .dailyBriefClient])`.

### 11.3 Integration tests

A minimal "boot the reducer with a fake container, assert ready in <100ms" test guards against future stages introducing surprise blocking work:

```swift
func test_bootstrap_completesUnderThreshold() async {
    let start = Date()
    let store = TestStore(...) { ... }
    await store.send(.start)
    // run through all expected receive() calls
    XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
}
```

---

## 12. Migration plan

Current state (as of 2026-05-13 staged-but-not-committed changes on `main`):

- [FromInkApp.swift](FromInk/FromInk/FromInkApp.swift) — `try! ModelContainer(...)` in `init`, calls `SyncedModelContextDependency.configure(with:)` directly.
- [SyncedModelContext.swift](FromInk/FromInk/App/Dependencies/SyncedModelContext.swift) — `@MainActor private var _sharedContext: ModelContext?` set via free `configure(with:)` function; `fatalError` if accessed pre-configure.
- [ContentView.swift](FromInk/FromInk/ContentView.swift) — fires `dailyBriefClient.fetchOrGenerate()` from `.task`, races with everything else.
- [HomeFeatureView.swift](FromInk/FromInk/rewrite/Home%20(needs%20work)/HomeFeatureView.swift) — runs a long-lived `for await ... calendarChanges()` from a view-level `.task`.
- No state machine. No retry. No surface for storage failure beyond `fatalError`.

### Migration steps

1. **Introduce `AppDependencyContainer`** as a sibling to `FromInkApp.swift`. Move every `liveValue` factory call out of `init()` and into a `private(set) lazy var`.
2. **Replace `SyncedModelContextDependency.configure(with:)` with constructor injection** via `.live(container:)`. Delete the file-scope `_sharedContext`. The fatal-error guard goes away.
3. **Add `BootstrapFeature`** scoped under `AppFeature`. Move the brief seed out of `ContentView.task` into `runBriefSeed()`. Move the calendar-changes subscription out of `HomeFeatureView.task` into `HomeFeature` — it's a feature-level long-lived effect, not bootstrap work.
4. **Replace `FromInkApp.init`'s `try!`** with the container's `Result`-typed `modelContainer`. The `try!` survives only inside `modelContainerForSwiftUI` as a last-resort fallback (§10.1).
5. **Add `BootstrapFailureView`.** Wire the retry action.
6. **Delete the launch-screen `Task.sleep(1.2s)` / `asyncAfter` delay**. Bootstrap is the timer now.
7. **Add `BootstrapFeatureTests`** covering happy path, storage failure, each degradation, retry.

Migration is mechanical and can ship behind no feature flag — the public surface (what reducers see via `@Dependency`) is unchanged.

---

## 13. Anti-patterns

- **`try!` outside the bootstrap path.** Every `try!` in the codebase should either be inside `AppDependencyContainer` (where failure is observable via `Result`) or replaced. Reducers never `try!`.
- **Reading from `AppDependencyContainer` outside `FromInkApp.init`.** If a reducer needs a value the container holds, the value belongs in `DependencyValues`.
- **`Task.sleep` or `DispatchQueue.asyncAfter` to "wait for boot."** Boot is a state machine; subscribe to the state.
- **Bootstrap effects fired from a SwiftUI `.task`.** The view tier doesn't own boot. If `BootstrapFeature.start` runs from a wiring view's `.task`, that is the *one* allowed exception — and only at the root.
- **`fatalError` for "not yet configured" dependencies.** Means construction order leaked. Use `Result` + a `.unavailable` variant, or make the dep lazy and let the container resolve it.
- **A stage that does both required and optional work.** Split it. `authRestore` is optional; `storage` is required; do not combine them into `setUpEverything`.
- **A new boot step added directly to `runStorage()`.** Each stage runs one operation. Composite work goes in `nextStage(after:state:)`.

---

## 14. Open questions

1. **Should `authRestore` be required when a session is present?** If the user has a valid keychain entry but token refresh fails (network down at launch), do we boot anyway and let them retry from the integration panel? Current proposal: optional, never blocks boot. Reconsider after dogfood.
2. **Is `featureFlags` worth a stage at all?** It could be a fire-and-forget background `Task` outside the reducer. The argument for a stage: surfaces "experiment X is on" before the home screen renders. The argument against: 99% of fetches are <50ms and the cost of blocking boot on a network call is not justified. Default in this EDD: keep it as an optional stage; revisit.
3. **Mac vs iOS divergence.** macOS has no `EventKitService.calendarAuthStatus` step in the current Mac shell. Two options: `#if os(iOS)` around the merged effect, or a `Stage.macSpecific` placeholder. Default: `#if`, since the divergence is small.
4. **How to test the SwiftUI `.modelContainer` modifier path.** `@Query`-based views can't be unit-tested with `TestStore`. Snapshot tests using `ModelConfiguration(isStoredInMemoryOnly: true)` are sufficient; integration tests rely on the simulator.
5. **Should `BootstrapFeature` live under `AppFeature` or be the root?** Default: child of `AppFeature` (so post-boot navigation state is owned by the parent). Inverting would simplify some scoping but couples navigation to bootstrap.

---

## 15. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-13 | Two registries: `AppDependencyContainer` (composition root) + `DependencyValues` (lookup). | Construction needs runtime configuration; lookup does not. Combining them produces the `fatalError` "not configured" pattern. |
| 2026-05-13 | Lazy `private(set) lazy var` per dependency. | Encodes the construction DAG via access order without a manual `setUp()` block. |
| 2026-05-13 | `modelContainer` is `Result`-typed, not throwing. | Throwing accessors couple construction failure to every call site. `Result` lets downstream lazies branch deterministically. |
| 2026-05-13 | `BootstrapFeature.Stage` enumerates required + optional stages; `Degradation` enumerates soft failures. | Two-axis model (stage × outcome) prevents the "is this an error or not" debate per stage. |
| 2026-05-13 | DAG centralized in `nextStage(after:state:)`. | Adding a stage edits one switch. Scattering branches across reducer cases (the obvious alternative) produces drift. |
| 2026-05-13 | Launch screen reads `phase` directly; no minimum-display timer. | Artificial delays mask boot regressions. If boot is fast, flicker is the correct outcome. |
| 2026-05-13 | `BootstrapFeature` lives under `AppFeature`, not at the root. | Keeps post-boot navigation state on the parent. Inverting is reconsidered if the boot-vs-navigation seam becomes awkward. |

