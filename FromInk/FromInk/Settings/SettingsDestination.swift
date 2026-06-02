/// Which sub-screen of the settings overlay is presented. `nil` (in
/// `SettingsFeature.State`) means the root settings list is showing.
///
/// `String` raw value gives us a stable, debuggable identity for
/// SwiftUI's ForEach when destinations drive `SettingsRowView` IDs.
///
enum SettingsDestination: String, Hashable, Sendable {
    case appearance
    case handedness
    case themes
    case permissions
}
