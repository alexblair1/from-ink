import SwiftUI

/// The brand's structural element — a 0.5-1pt separator line.
/// Sets editorial rhythm without asking for color.
///
///     HairlineRule()                      // horizontal, full width
///     HairlineRule(.vertical)             // vertical, full height
///     HairlineRule(thickness: 1)          // 1pt variant
///
struct HairlineRule: View {

    let axis: Axis
    let thickness: CGFloat
    let style: Style

    init(_ axis: Axis = .horizontal, thickness: CGFloat = 0.5, style: Style = .standard) {
        self.axis = axis
        self.thickness = thickness
        self.style = style
    }

    var body: some View {
        switch axis {
        case .horizontal:
            Rectangle()
                .fill(style.color)
                .frame(height: thickness)
        case .vertical:
            Rectangle()
                .fill(style.color)
                .frame(width: thickness)
        }
    }
}

// MARK: - Style

extension HairlineRule {
    struct Style {
        let color: Color

        static let standard = Style(
            color: ColorTokens.standard.separator
        )
    }
}
