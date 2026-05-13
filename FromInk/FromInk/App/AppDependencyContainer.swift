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
            let container = try ModelContainer(
                for: Notebook.self,
                     Folder.self,
                     RoutedItem.self,
                     DailyBriefRecord.self,
                     Item.self
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

    // MARK: - ML & Services

    private(set) lazy var foundationModelsService: FoundationModelsService = .liveValue

    private(set) lazy var eventKitService: EventKitService = .liveValue

    private(set) lazy var weatherService: WeatherDependency = .liveValue

    private(set) lazy var locationService: LocationService = .liveValue

    // MARK: - Composite

    private(set) lazy var dailyBriefClient: DailyBriefClient = {
        DailyBriefClient.live(
            modelContext: syncedModelContext,
            eventKit: eventKitService,
            foundationModels: foundationModelsService,
            calendarContext: calendarContext
        )
    }()

    // MARK: - Factories

    static func live() -> AppDependencyContainer { AppDependencyContainer() }

    // MARK: - Installation

    func install(into deps: inout DependencyValues) {
        deps.calendarContext = calendarContext
        deps.userPreferences = userPreferences
        deps.syncedModelContext = syncedModelContext
        deps.foundationModelsService = foundationModelsService
        deps.eventKitService = eventKitService
        deps.weatherService = weatherService
        deps.locationService = locationService
        deps.dailyBriefClient = dailyBriefClient
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
            return try! ModelContainer(
                for: Notebook.self,
                     Folder.self,
                     RoutedItem.self,
                     DailyBriefRecord.self,
                     Item.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
}
