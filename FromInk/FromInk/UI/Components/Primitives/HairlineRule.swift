import SwiftUI

/// The brand's structural element — a 0.5–1pt line in `ink/Rule`.
/// Sets editorial rhythm without asking for color.
///
///     HairlineRule()                      // horizontal, full width
///     HairlineRule(.vertical)             // vertical, full height
///     HairlineRule(thickness: 1)          // 1pt variant
///
struct HairlineRule: View {
    let axis: Axis
    let thickness: CGFloat

    init(_ axis: Axis = .horizontal, thickness: CGFloat = 0.5) {
        self.axis = axis
        self.thickness = thickness
    }

    var body: some View {
        switch axis {
        case .horizontal:
            Rectangle()
                .fill(Color("ink/Rule"))
                .frame(height: thickness)
        case .vertical:
            Rectangle()
                .fill(Color("ink/Rule"))
                .frame(width: thickness)
        }
    }
}
