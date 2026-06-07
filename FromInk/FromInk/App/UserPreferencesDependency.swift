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

    /// Whether the user has completed the onboarding flow.
    /// `true` only after the user reaches the final paywall screen
    /// and taps the primary CTA. Backing out, force-quitting, or
    /// failing the boot replays onboarding. Backed by the
    /// `"hasSeenOnboarding"` UserDefaults key.
    var loadHasSeenOnboarding: @Sendable () async -> Bool
    var markOnboardingCompleted: @Sendable () async -> Void

    /// In-progress onboarding step. Persisted across cold launches so
    /// that if iOS terminates the app while the user is in Settings
    /// (e.g. after tapping "Open Settings" from the permissions screen
    /// to grant calendar access), they resume on the same step rather
    /// than restarting at welcome.
    ///
    /// Returns `nil` when no progress has been saved (fresh install or
    /// after completion clears it).
    /// Backed by the `"onboardingStep"` UserDefaults key storing the
    /// step's raw value.
    var loadOnboardingStep: @Sendable () async -> OnboardingStep?
    /// Pass non-nil to record the step the user is being routed away
    /// from (i.e. before opening the system Settings app). Pass nil to
    /// clear the record (called on `sceneBecameActive` once the user
    /// has returned). User-initiated kills mid-onboarding never call
    /// this, so relaunching after a force-quit always lands at welcome.
    var saveOnboardingStep: @Sendable (OnboardingStep?) async -> Void
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
        },
        loadHasSeenOnboarding: {
            UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        },
        markOnboardingCompleted: {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            // Completion invalidates any in-progress step record.
            UserDefaults.standard.removeObject(forKey: "onboardingStep")
        },
        loadOnboardingStep: {
            UserDefaults.standard.string(forKey: "onboardingStep")
                .flatMap(OnboardingStep.init(rawValue:))
        },
        saveOnboardingStep: { step in
            if let step {
                UserDefaults.standard.set(step.rawValue, forKey: "onboardingStep")
            } else {
                UserDefaults.standard.removeObject(forKey: "onboardingStep")
            }
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
        saveHandedness: { _ in },
        loadHasSeenOnboarding: { true },
        markOnboardingCompleted: { },
        loadOnboardingStep: { nil },
        saveOnboardingStep: { _ in }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var userPreferences: UserPreferences {
        get { self[UserPreferences.self] }
        set { self[UserPreferences.self] = newValue }
    }
}
