import SwiftUI

/// User preference for app appearance.
/// Persisted by `UserPreferences.saveAppearance` / `.loadAppearance`
/// under the `"appearanceSetting"` UserDefaults key. `FromInkApp`
/// reads the same key via `@AppStorage` to apply the colorScheme at
/// the app root — both reads stay in sync because they share the
/// UserDefaults backing.
enum AppearanceSetting: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: AppStrings.Settings.systemAppearance
        case .light: AppStrings.Settings.lightAppearance
        case .dark: AppStrings.Settings.darkAppearance
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
