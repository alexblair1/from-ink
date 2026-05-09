import ComposableArchitecture
import Foundation

/// TCA dependency for reading/writing per-device user preferences.
/// Backed by UserPreferences SwiftData model in the local-only container.
///
struct UserPreferencesDependency: Sendable {
    var loadToolSettings: @Sendable () async -> IdentifiedArrayOf<ToolSettingsEntry>
    var saveToolSettings: @Sendable (ToolID, PenSettings) async -> Void
    var loadToolbarSide: @Sendable () async -> ToolbarSide
    var saveToolbarSide: @Sendable (ToolbarSide) async -> Void
    var loadActiveToolID: @Sendable () async -> ToolID
    var saveActiveToolID: @Sendable (ToolID) async -> Void
    var loadTemplate: @Sendable () async -> CanvasTemplate
    var saveTemplate: @Sendable (CanvasTemplate) async -> Void
}

// MARK: - DependencyKey

extension UserPreferencesDependency: DependencyKey {
    static var liveValue: UserPreferencesDependency {
        // TODO: Wire to UserPreferences SwiftData model in local container
        UserPreferencesDependency(
            loadToolSettings: { [] },
            saveToolSettings: { _, _ in },
            loadToolbarSide: { .left },
            saveToolbarSide: { _ in },
            loadActiveToolID: { .pen },
            saveActiveToolID: { _ in },
            loadTemplate: { .none },
            saveTemplate: { _ in }
        )
    }

    static var testValue: UserPreferencesDependency {
        UserPreferencesDependency(
            loadToolSettings: { [] },
            saveToolSettings: { _, _ in },
            loadToolbarSide: { .left },
            saveToolbarSide: { _ in },
            loadActiveToolID: { .pen },
            saveActiveToolID: { _ in },
            loadTemplate: { .none },
            saveTemplate: { _ in }
        )
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    var userPreferences: UserPreferencesDependency {
        get { self[UserPreferencesDependency.self] }
        set { self[UserPreferencesDependency.self] = newValue }
    }
}
