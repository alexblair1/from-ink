import SwiftUI

/// User preference for app appearance.
/// Stored as a raw `String` in `@AppStorage("appearanceSetting")`.
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
