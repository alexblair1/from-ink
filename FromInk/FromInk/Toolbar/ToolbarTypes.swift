import Foundation

/// Per-tool settings persisted across sessions.
///
struct ToolSettingsEntry: Identifiable, Equatable, Codable, Sendable {
    let id: ToolID
    var settings: PenSettings
}

/// What panel is currently open, if any.
///
enum PanelKind: Equatable, Sendable {
    case toolCustomization(ToolID)
    case templatePicker
    case canvasSettings
}

/// Which side of the screen the toolbar is on.
///
enum ToolbarSide: String, Equatable, Codable, Sendable {
    case left, right
}

/// Typed identifiers for toolbar action buttons.
///
enum ToolbarActionID: String, Equatable, Sendable {
    case undo
    case redo
    case template
    case settings
}
