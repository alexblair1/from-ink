import Foundation

/// Per-tool settings persisted across sessions.
///
struct ToolSettingsEntry: @preconcurrency Identifiable, Equatable, Codable, Sendable {
    let id: ToolID
    var settings: PenSettings
}
