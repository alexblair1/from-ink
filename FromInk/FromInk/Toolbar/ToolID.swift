import Foundation

/// Unique identity for a tool. String-backed for persistence and extensibility.
/// Adding a tool does not require modifying this type — add a new static constant.
///
/// Explicitly nonisolated because the project uses SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
/// TCA's @Reducer macro requires these types to be usable across actor boundaries.
///
nonisolated
struct ToolID: Hashable, Codable, RawRepresentable, Sendable {
    nonisolated let rawValue: String

    nonisolated static let pen = ToolID(rawValue: "pen")
    nonisolated static let fountain = ToolID(rawValue: "fountain")
    nonisolated static let pencil = ToolID(rawValue: "pencil")
    nonisolated static let marker = ToolID(rawValue: "marker")
    nonisolated static let highlighter = ToolID(rawValue: "highlighter")
    nonisolated static let eraser = ToolID(rawValue: "eraser")
    nonisolated static let lasso = ToolID(rawValue: "lasso")
}
