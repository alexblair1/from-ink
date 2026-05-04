import UIKit
import SwiftUI

/// A non-interactive UIView that renders the active canvas template at full page height.
/// Inserted as the bottom-most subview of PKCanvasView so it scrolls with the content.
final class PageTemplateLayer: UIView {

    var template: CanvasTemplate = .none {
        didSet { if oldValue != template { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let size = bounds.size
        let lineColor = UIColor(Color.ruleLine)

        switch template {
        case .none:
            break
        case .linesWide, .linesCollege, .linesNarrow:
            drawHorizontalLines(ctx, size, template.spacing, lineColor)
        case .grid:
            drawHorizontalLines(ctx, size, template.spacing, lineColor)
            drawVerticalLines(ctx, size, template.spacing, lineColor)
        case .dots:
            drawDots(ctx, size, template.spacing, lineColor)
        case .isometric:
            drawIsometric(ctx, size, template.spacing, lineColor)
        }

        drawPageBottom(ctx, size, lineColor)
    }

    // MARK: - Primitives

    private func drawHorizontalLines(_ ctx: CGContext, _ size: CGSize, _ spacing: CGFloat, _ color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5)
        var y = spacing
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawVerticalLines(_ ctx: CGContext, _ size: CGSize, _ spacing: CGFloat, _ color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5)
        var x = spacing
        while x < size.width {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawDots(_ ctx: CGContext, _ size: CGSize, _ spacing: CGFloat, _ color: UIColor) {
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        let r: CGFloat = 1.0
        var y = spacing
        while y < size.height {
            var x = spacing
            while x < size.width {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += spacing
            }
            y += spacing
        }
        ctx.restoreGState()
    }

    private func drawIsometric(_ ctx: CGContext, _ size: CGSize, _ spacing: CGFloat, _ color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5)

        let rowH = spacing * sin(.pi / 3)
        let run  = size.height / tan(.pi / 3)

        // Horizontal lines
        var y = rowH
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
            y += rowH
        }

        // Diagonals ↘
        var x0 = -run
        while x0 < size.width {
            ctx.move(to: CGPoint(x: x0, y: 0))
            ctx.addLine(to: CGPoint(x: x0 + run, y: size.height))
            x0 += spacing
        }

        // Diagonals ↙
        var x1: CGFloat = 0
        while x1 < size.width + run {
            ctx.move(to: CGPoint(x: x1, y: 0))
            ctx.addLine(to: CGPoint(x: x1 - run, y: size.height))
            x1 += spacing
        }

        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Page bottom

    private func drawPageBottom(_ ctx: CGContext, _ size: CGSize, _ lineColor: UIColor) {
        let bottomY = size.height - 32
        // Stronger end-of-page line
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.withAlphaComponent(2.5).cgColor)
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: 32, y: bottomY))
        ctx.addLine(to: CGPoint(x: size.width - 32, y: bottomY))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
