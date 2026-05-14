import SwiftUI

/// Single-sentence standfirst below the date.
/// New York 19 light.
/// Component view — no TCA imports.
///
struct BriefLede: View {
    let model: Model

    var body: some View {
        Text(model.text)
            .font(model.font)
            .foregroundStyle(model.color)
            .lineSpacing(model.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, model.horizontalPadding)
            .padding(.top, model.topPadding)
    }
}

// MARK: - Model

extension BriefLede {
    struct Model {
        let text: String
        let font: Font
        let color: Color
        let lineSpacing: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
    }
}

// MARK: - Model init

extension BriefLede.Model {
    init(
        text: String,
        ds: DesignSystem = .standard
    ) {
        self.text = text
        self.font = ds.typography.briefLede
        self.color = ds.colors.ink
        self.lineSpacing = ds.spacing.xs
        self.horizontalPadding = ds.spacing.lg
        self.topPadding = ds.spacing.sm
    }
}
