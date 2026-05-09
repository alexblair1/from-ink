import PencilKit

/// Declares a tool's identity, icon, label, and PencilKit mapping.
/// The toolbar view does not know what a tool does — it renders an icon and forwards taps.
///
/// `Equatable` conformance compares by `id` only (IDs are unique).
///
struct ToolDescriptor: Sendable {
    let id: ToolID
    let icon: String
    let label: String
    let hasCustomization: Bool
    let makePKTool: @Sendable (PenSettings) -> PKTool
}

// MARK: - Equatable (by id)

extension ToolDescriptor: Equatable {
    static func == (lhs: ToolDescriptor, rhs: ToolDescriptor) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Built-in descriptors

extension ToolDescriptor {
    static let pen = ToolDescriptor(
        id: .pen, icon: "pencil", label: "Pen",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let fountain = ToolDescriptor(
        id: .fountain, icon: "pencil.tip", label: "Fountain",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let pencil = ToolDescriptor(
        id: .pencil, icon: "scribble", label: "Pencil",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let marker = ToolDescriptor(
        id: .marker, icon: "paintbrush.pointed", label: "Marker",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let highlighter = ToolDescriptor(
        id: .highlighter, icon: "highlighter", label: "Highlighter",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let eraser = ToolDescriptor(
        id: .eraser, icon: "eraser", label: "Eraser",
        hasCustomization: false,
        makePKTool: { _ in PKEraserTool(.bitmap) }
    )

    static let lasso = ToolDescriptor(
        id: .lasso, icon: "lasso", label: "Lasso",
        hasCustomization: false,
        makePKTool: { _ in PKLassoTool() }
    )

    /// The ordered set of all writing tools. Toolbar renders from this array.
    static let allWritingTools: [ToolDescriptor] = [
        .pen, .fountain, .pencil, .marker, .highlighter, .eraser, .lasso
    ]
}
