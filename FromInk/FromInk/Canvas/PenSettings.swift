import SwiftUI
import PencilKit

struct PenSettings: Equatable {

    // MARK: - Pen Type

    enum PenType: String, CaseIterable, Equatable {
        case ballpoint, fineliner, pencil, mechanical, fountain, paintbrush, calligraphy, marker, highlighter

        var displayName: String {
            switch self {
            case .ballpoint:  return "Ballpoint"
            case .fineliner:  return "Fineliner"
            case .pencil:     return "Pencil"
            case .mechanical: return "Mechanical"
            case .fountain:   return "Fountain"
            case .paintbrush: return "Paintbrush"
            case .calligraphy:return "Calligraphy"
            case .marker:     return "Marker"
            case .highlighter:return "Highlighter"
            }
        }

        var icon: String {
            switch self {
            case .ballpoint:  return "pencil"
            case .fineliner:  return "line.diagonal"
            case .pencil:     return "pencil.tip"
            case .mechanical: return "pencil.circle"
            case .fountain:   return "paintbrush.pointed"
            case .paintbrush: return "paintbrush"
            case .calligraphy:return "scribble"
            case .marker:     return "paintbrush.pointed.fill"
            case .highlighter:return "highlighter"
            }
        }

        var inkType: PKInkingTool.InkType {
            switch self {
            case .ballpoint:  return .pen
            case .fineliner:  return .monoline
            case .pencil:     return .pencil
            case .mechanical: return .monoline
            case .fountain:   return .fountainPen
            case .paintbrush: return .watercolor
            case .calligraphy:return .fountainPen
            case .marker:     return .marker
            case .highlighter:return .marker
            }
        }

        var isHighlighter: Bool { self == .highlighter }
    }

    // MARK: - Graphite Grade

    enum GraphiteGrade: Int, CaseIterable, Equatable {
        case nineH = 0, threeH, hb, threeB, nineB

        var label: String {
            switch self {
            case .nineH:  return "9H"
            case .threeH: return "3H"
            case .hb:     return "HB"
            case .threeB: return "3B"
            case .nineB:  return "9B"
            }
        }

        var uiColor: UIColor {
            switch self {
            case .nineH:  return UIColor(white: 0.72, alpha: 1)
            case .threeH: return UIColor(white: 0.52, alpha: 1)
            case .hb:     return UIColor(white: 0.28, alpha: 1)
            case .threeB: return UIColor(white: 0.10, alpha: 1)
            case .nineB:  return UIColor(white: 0.00, alpha: 1)
            }
        }
    }

    // MARK: - Properties

    var penType: PenType = .ballpoint
    var thicknessIndex: Int = 1
    var grade: GraphiteGrade = .hb
    var highlighterColorIndex: Int = 0

    // MARK: - Palettes

    static let thicknesses: [CGFloat] = [0.5, 1.5, 3, 5, 8]

    static let highlighterColors: [Color] = [
        Color(red: 1.00, green: 0.92, blue: 0.23),  // yellow
        Color(red: 0.35, green: 0.90, blue: 0.45),  // green
        Color(red: 0.35, green: 0.65, blue: 1.00),  // blue
        Color(red: 1.00, green: 0.45, blue: 0.75),  // pink
        Color(red: 1.00, green: 0.62, blue: 0.25),  // orange
    ]

    static let `default` = PenSettings()

    // MARK: - PencilKit

    var pkTool: PKTool {
        if penType.isHighlighter {
            let color = UIColor(Self.highlighterColors[highlighterColorIndex])
                .withAlphaComponent(0.4)
            return PKInkingTool(.marker, color: color, width: 18)
        }
        let width = Self.thicknesses[thicknessIndex]
        let adjustedWidth = penType == .calligraphy ? width * 2 : width
        return PKInkingTool(penType.inkType, color: grade.uiColor, width: adjustedWidth)
    }
}
