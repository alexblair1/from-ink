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

    /// Light / Dark / System override. Read at app root by
    /// `FromInkApp.appearance`; written by `SettingsFeature`.
    /// Backed by the `"appearanceSetting"` UserDefaults key so the
    /// app-root `@AppStorage` reader sees the same value the reducer
    /// writes — no second source of truth.
    var loadAppearance: @Sendable () async -> AppearanceSetting
    var saveAppearance: @Sendable (AppearanceSetting) async -> Void

    /// Left / Right hand preference. Maps to `ToolbarSide` at the
    /// canvas via `Handedness.toolbarSide`. Backed by the
    /// `"handedness"` UserDefaults key.
    var loadHandedness: @Sendable () async -> Handedness
    var saveHandedness: @Sendable (Handedness) async -> Void
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
        saveTemplate: { _ in },
        loadAppearance: {
            UserDefaults.standard.string(forKey: "appearanceSetting")
                .flatMap(AppearanceSetting.init(rawValue:))
                ?? .system
        },
        saveAppearance: { setting in
            UserDefaults.standard.set(setting.rawValue, forKey: "appearanceSetting")
        },
        loadHandedness: {
            UserDefaults.standard.string(forKey: "handedness")
                .flatMap(Handedness.init(rawValue:))
                ?? .right
        },
        saveHandedness: { handedness in
            UserDefaults.standard.set(handedness.rawValue, forKey: "handedness")
        }
    )

    static let testValue = UserPreferences(
        loadToolSettings: { [] },
        saveToolSettings: { _, _ in },
        loadToolbarSide: { .left },
        saveToolbarSide: { _ in },
        loadActiveToolID: { ToolID(rawValue: "pen") },
        saveActiveToolID: { _ in },
        loadTemplate: { .none },
        saveTemplate: { _ in },
        loadAppearance: { .system },
        saveAppearance: { _ in },
        loadHandedness: { .right },
        saveHandedness: { _ in }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var userPreferences: UserPreferences {
        get { self[UserPreferences.self] }
        set { self[UserPreferences.self] = newValue }
    }
}
