import PencilKit
import SwiftUI

// MARK: - Tool

enum CanvasTool: String, CaseIterable, Equatable {
    case pen
    case fountain
    case pencil
    case marker
    case highlighter
    case eraser
    case lasso

    func pkTool(settings: PenSettings = .default) -> PKTool {
        switch self {
        case .pen, .fountain, .pencil, .marker, .highlighter:
            return settings.pkTool
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
