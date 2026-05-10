import CoreGraphics

enum CanvasTemplate: String, CaseIterable, Equatable, Codable, Sendable, Hashable {
    case none
    case linesWide
    case linesCollege
    case linesNarrow
    case grid
    case dots
    case isometric

    var displayName: String {
        switch self {
        case .none:         return "None"
        case .linesWide:    return "Wide Ruled"
        case .linesCollege: return "College Ruled"
        case .linesNarrow:  return "Narrow Ruled"
        case .grid:         return "Grid"
        case .dots:         return "Dots"
        case .isometric:    return "Isometric"
        }
    }

    /// Spacing in points between lines/grid cells on a full-size canvas
    var spacing: CGFloat {
        switch self {
        case .linesWide:    return 56
        case .linesCollege: return 44
        case .linesNarrow:  return 32
        case .grid:         return 40
        case .dots:         return 40
        case .isometric:    return 32
        case .none:         return 0
        }
    }

    /// Scaled spacing for 36pt thumbnail previews
    var thumbnailSpacing: CGFloat {
        switch self {
        case .none:      return 0
        default:         return max(4, spacing / 7)
        }
    }
}
