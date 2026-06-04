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

    private(set) lazy var calendarContext: CalendarContext = .liveValue

    private(set) lazy var userPreferences: UserPreferences = .liveValue

    // MARK: - Storage

    private(set) lazy var modelContainer: Result<ModelContainer, BootstrapError> = {
        do {
            let schema = Schema(FromInkSchemaV1.models)
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none   // Phase 1 — see data_model_edd.md §9
            )
            // No `migrationPlan:` — SwiftData uses default lightweight
            // migration (handles additive changes automatically). The
            // `FromInkMigrationPlan` skeleton lives in source for the
            // Phase 2 lock-in; passing it with empty stages confuses
            // SwiftData into "no migrations possible" mode and blocks
            // even the lightweight path. Wire it back in when we add
            // the first explicit stage.
            let container = try ModelContainer(
                for: schema,
                configurations: config
            )
            return .success(container)
        } catch {
            log.error("ModelContainer init failed: \(error)")
            return .failure(.storageUnavailable(error))
        }
    }()

    private(set) lazy var syncedModelContext: SyncedModelContextDependency = {
        switch modelContainer {
        case .success(let container):
            return .live(container: container)
        case .failure:
            return .unavailable
        }
    }()

    /// Local-only container for per-device data (UserPreferencesRecord).
    /// `cloudKitDatabase: .none` forever — this container never syncs.
    ///
    /// **Important:** must use an explicit URL distinct from the synced
    /// container. Two `ModelContainer`s pointing at the default URL
    /// (`Application Support/default.store`) collide and corrupt each
    /// other's schema — symptom is persistent "no such table: ZNOTEBOOK"
    /// errors after the second container truncates the first's tables.
    private(set) lazy var localContainer: Result<ModelContainer, BootstrapError> = {
        do {
            let schema = Schema([UserPreferencesRecord.self])
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let url = appSupport.appendingPathComponent("fromink-local.store")
            let config = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                configurations: config
            )
            return .success(container)
        } catch {
            log.error("Local ModelContainer init failed: \(error)")
            return .failure(.storageUnavailable(error))
        }
    }()

    private(set) lazy var localModelContext: LocalModelContextDependency = {
        switch localContainer {
        case .success(let container):
            return .live(container: container)
        case .failure:
            return .unavailable
        }
    }()

    // MARK: - ML & Services

    private(set) lazy var foundationModelsService: FoundationModelsService = .liveValue

    private(set) lazy var eventKitService: EventKitService = .liveValue

    private(set) lazy var weatherService: WeatherDependency = .liveValue

    private(set) lazy var locationService: LocationService = .liveValue

    // MARK: - Auth

    private(set) lazy var keychainService: KeychainService = .liveValue

    private(set) lazy var backgroundTokenRefresh: BackgroundTokenRefreshService = .liveValue

    private(set) lazy var oauthService: OAuthService = {
        OAuthService.live(
            keychain: keychainService,
            calendarContext: calendarContext
        )
    }()

    // MARK: - Composite

    private(set) lazy var dailyBriefClient: DailyBriefClient = {
        DailyBriefClient.live(
            modelContext: syncedModelContext,
            eventKit: eventKitService,
            foundationModels: foundationModelsService,
            calendarContext: calendarContext
        )
    }()

    private(set) lazy var notebookClient: NotebookClient = {
        NotebookClient.live(
            modelContext: syncedModelContext,
            calendarContext: calendarContext
        )
    }()

    private(set) lazy var calendarItemLinkService: CalendarItemLinkService = {
        let ctxDep = syncedModelContext
        let cal = calendarContext
        return CalendarItemLinkService.live(
            context: { @MainActor in ctxDep.context() },
            now: { cal.now() }
        )
    }()

    private(set) lazy var calendarItemLinkValidator: CalendarItemLinkValidator = {
        let brief = dailyBriefClient
        return CalendarItemLinkValidator.live(
            linkService: calendarItemLinkService,
            eventKit: eventKitService,
            calendarChanges: { brief.calendarChanges() },
            clock: ContinuousClock()
        )
    }()

    // MARK: - Factories

    static func live() -> AppDependencyContainer { AppDependencyContainer() }

    // MARK: - Installation

    func install(into deps: inout DependencyValues) {
        deps.calendarContext = calendarContext
        deps.userPreferences = userPreferences
        deps.syncedModelContext = syncedModelContext
        deps.localModelContext = localModelContext
        deps.foundationModelsService = foundationModelsService
        deps.eventKitService = eventKitService
        deps.weatherService = weatherService
        deps.locationService = locationService
        deps.keychainService = keychainService
        deps.oauthService = oauthService
        deps.backgroundTokenRefresh = backgroundTokenRefresh
        deps.dailyBriefClient = dailyBriefClient
        deps.notebookClient = notebookClient
        deps.calendarItemLinkService = calendarItemLinkService
        deps.calendarItemLinkValidator = calendarItemLinkValidator
    }

    // MARK: - SwiftUI bridge

    /// Provides a ModelContainer for the SwiftUI `.modelContainer` modifier.
    /// Both @Query views and @Dependency(\.syncedModelContext) resolve to the same instance.
    var modelContainerForSwiftUI: ModelContainer {
        switch modelContainer {
        case .success(let c):
            return c
        case .failure:
            // Fallback ephemeral container — the app is in .failed phase;
            // views behind BootstrapFailureView will not be visible.
            let schema = Schema(FromInkSchemaV1.models)
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            )
        }
    }
}
