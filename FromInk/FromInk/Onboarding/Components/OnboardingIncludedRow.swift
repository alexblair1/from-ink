import SwiftUI

/// One row in the subscription screen's "included" list — checkmark plus
/// a sans label, with a 1pt translucent rule beneath each row.
///
struct OnboardingIncludedRow: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: model.iconSpacing) {
                Image(systemName: model.icon)
                    .font(model.iconFont)
                    .foregroundStyle(model.iconColor)
                    .symbolRenderingMode(.monochrome)
                    .accessibilityHidden(true)

                Text(model.text)
                    .font(model.textFont)
                    .foregroundStyle(model.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, model.rowVerticalPadding)

            Rectangle()
                .fill(model.dividerColor)
                .frame(height: model.dividerHeight)
        }
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingIncludedRow {
    struct Model: Equatable, Identifiable {
        let id: String
        let icon: String
        let text: String
        let iconFont: Font
        let iconColor: Color
        let iconSpacing: CGFloat
        let textFont: Font
        let textColor: Color
        let rowVerticalPadding: CGFloat
        let dividerColor: Color
        let dividerHeight: CGFloat
    }
}

extension OnboardingIncludedRow.Model {
    init(id: String, icon: String, text: String, ds: DesignSystem = .standard) {
        self.id = id
        self.icon = icon
        self.text = text
        self.iconFont = .system(.title3, weight: .regular)
        self.iconColor = ds.colors.ink
        self.iconSpacing = ds.spacing.md
        self.textFont = .system(.callout, design: .default)
        self.textColor = ds.colors.ink
        self.rowVerticalPadding = ds.spacing.md
        self.dividerColor = ds.colors.rule.opacity(0.5)
        self.dividerHeight = ds.layout.borderWidth
    }
}
