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
    /// Region-marking tool — same `PKLassoTool` mechanic as `.lasso`,
    /// but the Coordinator captures `wantsBrandedLasso = true` at
    /// lasso-begin so the branded `LassoMenuBar` fires on completion.
    /// `.lasso` sessions don't set that flag and produce no menu —
    /// they're bare PKLassoTool (select + drag-to-move). System
    /// Copy / Cut / Paste affordances would require explicit
    /// `UIEditMenuInteraction` wiring on the canvas; a follow-up
    /// PR can add that if `.lasso` parity with Apple Notes is wanted.
    ///
    /// This is the one-handed entry point to creating a `NoteRegion`
    /// (header / link / event / reminder anchor). The existing
    /// two-finger hold gesture also pushes this tool onto `toolStack`.
    static let region = ToolID(rawValue: "region")
}
