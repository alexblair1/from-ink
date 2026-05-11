/// What panel is currently open, if any.
///
enum PanelKind: Equatable, Sendable {
    case toolCustomization(ToolID)
    case templatePicker
    case canvasSettings
}
