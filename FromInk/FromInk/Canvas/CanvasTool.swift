import PencilKit

// MARK: - Tool

enum CanvasTool: String, CaseIterable, Equatable {
    case pen
    case fountain
    case pencil
    case marker
    case highlighter
    case eraser
    case lasso

    var pkTool: PKTool {
        switch self {
        case .pen:
            return PKInkingTool(.pen, color: .black, width: 2)
        case .fountain:
            return PKInkingTool(.fountainPen, color: .black, width: 3)
        case .pencil:
            return PKInkingTool(.pencil, color: .black, width: 3)
        case .marker:
            return PKInkingTool(.marker, color: .black, width: 10)
        case .highlighter:
            return PKInkingTool(.marker, color: .systemYellow.withAlphaComponent(0.4), width: 18)
        case .eraser:
            return PKEraserTool(.bitmap)
        case .lasso:
            return PKLassoTool()
        }
    }

    var icon: String {
        switch self {
        case .pen:         return "pencil"
        case .fountain:    return "pencil.tip"
        case .pencil:      return "scribble"
        case .marker:      return "paintbrush.pointed"
        case .highlighter: return "highlighter"
        case .eraser:      return "eraser"
        case .lasso:       return "lasso"
        }
    }
}

// MARK: - Toolbar Side

enum ToolbarSide: String {
    case left, right
}
