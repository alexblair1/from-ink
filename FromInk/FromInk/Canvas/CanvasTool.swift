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
    /// Region tool — same `PKLassoTool` mechanic as `.lasso`. The
    /// branded-vs-bare distinction is upstream (the Coordinator's
    /// `wantsBrandedLasso` flag); from PencilKit's perspective both
    /// produce a selection.
    case region

    func pkTool(settings: PenSettings = .default) -> PKTool {
        switch self {
        case .pen, .fountain, .pencil, .marker, .highlighter:
            return settings.pkTool
        case .eraser:
            return PKEraserTool(.bitmap)
        case .lasso, .region:
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
        case .region:      return "rectangle.dashed"
        }
    }

    /// True for tools backed by `PKLassoTool`. The canvas uses this to
    /// gate the lasso-bounds pan recognizer + the lasso-end callback
    /// guards. Adding a third lasso-backed tool would only need a case
    /// added here, not three separate `||` updates scattered through
    /// CanvasView.
    var producesLassoSelection: Bool {
        switch self {
        case .lasso, .region: return true
        case .pen, .fountain, .pencil, .marker, .highlighter, .eraser:
            return false
        }
    }
}

// ToolbarSide is defined in Toolbar/ToolbarTypes.swift
