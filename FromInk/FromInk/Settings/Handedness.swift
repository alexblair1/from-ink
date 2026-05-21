import Foundation

/// User preference for handedness — determines which side of the
/// canvas the writing hand occupies, and consequently where the
/// toolbar lives.
///
/// Persisted by `UserPreferences.saveHandedness` / `.loadHandedness`
/// under the `"handedness"` UserDefaults key. Maps to the toolbar's
/// existing `ToolbarSide` enum at the point of use via the
/// `toolbarSide` property — right-handed → toolbar on the left, and
/// vice versa.
///
enum Handedness: String, CaseIterable {
    case right
    case left

    var label: String {
        switch self {
        case .right: AppStrings.Settings.rightHanded
        case .left:  AppStrings.Settings.leftHanded
        }
    }

    /// The side the toolbar should occupy given this handedness.
    /// Right-handed users want the toolbar on the LEFT so their
    /// writing hand has clear access to the canvas; left-handed
    /// users want it on the right.
    var toolbarSide: ToolbarSide {
        switch self {
        case .right: .left
        case .left:  .right
        }
    }
}
