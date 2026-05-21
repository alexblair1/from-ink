/// Which sub-screen of the settings overlay is presented. `nil` (in
/// `SettingsFeature.State`) means the root settings list is showing.
///
enum SettingsDestination: Hashable, Sendable {
    case appearance
    case handedness
    case themes
    case integrations
    case permissions
}
