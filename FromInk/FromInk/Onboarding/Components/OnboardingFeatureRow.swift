import SwiftUI

/// One row in the value screen's "The idea" list.
/// 30pt icon column + text column with mono eyebrow, serif title, sans body.
/// Rows are separated by a 1pt rule with a translucent ink color; the last
/// row in a list passes `last: true` to suppress its bottom border.
///
struct OnboardingFeatureRow: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: model.iconSpacing) {
                Image(systemName: model.icon)
                    .font(model.iconFont)
                    .foregroundStyle(model.iconColor)
                    .symbolRenderingMode(.monochrome)
                    .frame(minWidth: model.iconMinWidth, alignment: .leading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.kicker)
                        .font(model.kickerFont)
                        .tracking(model.kickerTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(model.kickerColor)
                        .padding(.bottom, model.kickerBottomPadding)

                    Text(model.title)
                        .font(model.titleFont)
                        .foregroundStyle(model.titleColor)

                    Text(model.body)
                        .font(model.bodyFont)
                        .foregroundStyle(model.bodyColor)
                        .lineSpacing(model.bodyLineSpacing)
                        .padding(.top, model.bodyTopPadding)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, model.rowVerticalPadding)

            if !model.isLast {
                Rectangle()
                    .fill(model.dividerColor)
                    .frame(height: model.dividerHeight)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingFeatureRow {
    struct Model: Equatable, Identifiable {
        let id: String
        let icon: String
        let kicker: String
        let title: String
        let body: String
        let isLast: Bool
        let iconFont: Font
        let iconColor: Color
        let iconMinWidth: CGFloat
        let iconSpacing: CGFloat
        let kickerFont: Font
        let kickerColor: Color
        let kickerTracking: CGFloat
        let kickerBottomPadding: CGFloat
        let titleFont: Font
        let titleColor: Color
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let bodyTopPadding: CGFloat
        let rowVerticalPadding: CGFloat
        let dividerColor: Color
        let dividerHeight: CGFloat
    }
}

extension OnboardingFeatureRow.Model {
    init(
        id: String,
        icon: String,
        kicker: String,
        title: String,
        body: String,
        isLast: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.icon = icon
        self.kicker = kicker
        self.title = title
        self.body = body
        self.isLast = isLast
        self.iconFont = .system(.title3, design: .default)
        self.iconColor = ds.colors.ink
        self.iconMinWidth = ds.layout.onboardingFeatureRowIconColumn
        self.iconSpacing = ds.spacing.base
        self.kickerFont = ds.typography.onboardingKicker
        self.kickerColor = ds.colors.ink2
        self.kickerTracking = ds.typography.kickerTracking
        self.kickerBottomPadding = ds.spacing.xs
        self.titleFont = .system(.title3, design: .serif)
        self.titleColor = ds.colors.ink
        self.bodyFont = .system(.subheadline, design: .default)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.xxs
        self.bodyTopPadding = ds.spacing.xs
        self.rowVerticalPadding = ds.spacing.base
        self.dividerColor = ds.colors.rule.opacity(0.6)
        self.dividerHeight = ds.layout.borderWidth
    }
}
