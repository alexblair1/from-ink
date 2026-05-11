import ComposableArchitecture
import Foundation

/// TCA dependency for reading/writing per-device user preferences.
/// Backed by UserPreferences SwiftData model in the local-only container.
///
struct UserPreferences: Sendable {
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

extension UserPreferences: DependencyKey {
    static let liveValue = UserPreferences(
        // TODO: Wire to UserPreferences SwiftData model in local container
        loadToolSettings: { [] },
        saveToolSettings: { _, _ in },
        loadToolbarSide: { .left },
        saveToolbarSide: { _ in },
        loadActiveToolID: { ToolID(rawValue: "pen") },
        saveActiveToolID: { _ in },
        loadTemplate: { .none },
        saveTemplate: { _ in }
    )

    static let testValue = UserPreferences(
        loadToolSettings: { [] },
        saveToolSettings: { _, _ in },
        loadToolbarSide: { .left },
        saveToolbarSide: { _ in },
        loadActiveToolID: { ToolID(rawValue: "pen") },
        saveActiveToolID: { _ in },
        loadTemplate: { .none },
        saveTemplate: { _ in }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var userPreferences: UserPreferences {
        get { self[UserPreferences.self] }
        set { self[UserPreferences.self] = newValue }
    }
}
