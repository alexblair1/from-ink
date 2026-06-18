import SwiftUI

struct TemplateView: View {
    let template: CanvasTemplate
    var spacingOverride: CGFloat? = nil

    private var spacing: CGFloat { spacingOverride ?? template.spacing }

    var body: some View {
        Canvas { context, size in
            Self.draw(template, in: context, size: size, spacing: spacing)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Static drawing (shared with thumbnail)

    static func draw(
        _ template: CanvasTemplate,
        in context: GraphicsContext,
        size: CGSize,
        spacing: CGFloat
    ) {
        let color = GraphicsContext.Shading.color(DesignSystem.standard.colors.ruleLine)
        switch template {
        case .none:
            break
        case .linesWide, .linesCollege, .linesNarrow:
            horizontalLines(context, size, spacing, color)
        case .grid:
            horizontalLines(context, size, spacing, color)
            verticalLines(context, size, spacing, color)
        case .dots:
            dots(context, size, spacing, color)
        case .isometric:
            isometric(context, size, spacing, color)
        }
    }

    // MARK: - Primitives

    private static func horizontalLines(
        _ ctx: GraphicsContext, _ size: CGSize,
        _ spacing: CGFloat, _ color: GraphicsContext.Shading
    ) {
        var y = spacing
        while y < size.height {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: color, lineWidth: 0.5)
            y += spacing
        }
    }

    private static func verticalLines(
        _ ctx: GraphicsContext, _ size: CGSize,
        _ spacing: CGFloat, _ color: GraphicsContext.Shading
    ) {
        var x = spacing
        while x < size.width {
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(p, with: color, lineWidth: 0.5)
            x += spacing
        }
    }

    private static func dots(
        _ ctx: GraphicsContext, _ size: CGSize,
        _ spacing: CGFloat, _ color: GraphicsContext.Shading
    ) {
        let r: CGFloat = 1.0
        var y = spacing
        while y < size.height {
            var x = spacing
            while x < size.width {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: color
                )
                x += spacing
            }
            y += spacing
        }
    }

    private static func isometric(
        _ ctx: GraphicsContext, _ size: CGSize,
        _ spacing: CGFloat, _ color: GraphicsContext.Shading
    ) {
        // Three sets of lines at 60° intervals: horizontal, +60°, -60°
        let rowH = spacing * sin(.pi / 3)   // spacing × √3/2
        let run  = size.height / tan(.pi / 3) // horizontal run for a diagonal spanning full height

        // Horizontal lines
        var y = rowH
        while y < size.height {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: color, lineWidth: 0.5)
            y += rowH
        }

        // Diagonals going down-right (↘)
        var x0 = -run
        while x0 < size.width {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: 0))
            p.addLine(to: CGPoint(x: x0 + run, y: size.height))
            ctx.stroke(p, with: color, lineWidth: 0.5)
            x0 += spacing
        }

        // Diagonals going down-left (↙)
        var x1: CGFloat = 0
        while x1 < size.width + run {
            var p = Path()
            p.move(to: CGPoint(x: x1, y: 0))
            p.addLine(to: CGPoint(x: x1 - run, y: size.height))
            ctx.stroke(p, with: color, lineWidth: 0.5)
            x1 += spacing
        }
    }
}
