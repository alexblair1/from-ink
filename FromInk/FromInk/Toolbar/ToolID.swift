import Foundation

/// Unique identity for a tool. String-backed for persistence and extensibility.
/// Adding a tool does not require modifying this type — add a new static constant.
///
struct ToolID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: String

    static let pen = ToolID(rawValue: "pen")
    static let fountain = ToolID(rawValue: "fountain")
    static let pencil = ToolID(rawValue: "pencil")
    static let marker = ToolID(rawValue: "marker")
    static let highlighter = ToolID(rawValue: "highlighter")
    static let eraser = ToolID(rawValue: "eraser")
    static let lasso = ToolID(rawValue: "lasso")
}
