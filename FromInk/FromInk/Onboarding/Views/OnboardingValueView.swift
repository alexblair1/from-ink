import SwiftUI

/// Value screen ("The idea") — kicker, two-tone headline, three feature
/// rows separated by hairline rules.
///
/// The headline is composed of two localized strings concatenated with
/// a single space and styled as one continuous flowing block — no
/// hardcoded `\n`. It wraps based on available width, so long-locale
/// translations and large Dynamic Type sizes both reflow gracefully.
/// All text uses system text styles (Dynamic Type-aware).
///
struct OnboardingValueView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingKicker(model: model.kicker)
                .padding(.bottom, model.kickerBottomPadding)

            (Text(model.headlineLine1)
                .foregroundStyle(model.headlineColor)
             + Text(verbatim: " ")
             + Text(model.headlineLine2)
                .italic()
                .foregroundStyle(model.headlineAccentColor))
                .font(model.headlineFont)
                .lineSpacing(model.headlineLineSpacing)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Rectangle()
                .fill(model.topRuleColor)
                .frame(height: model.ruleHeight)
                .padding(.top, model.topRuleTopPadding)

            ForEach(model.rows) { row in
                OnboardingFeatureRow(model: row)
            }
        }
    }
}

extension OnboardingValueView {
    struct Model {
        let kicker: OnboardingKicker.Model
        let headlineLine1: String
        let headlineLine2: String
        let rows: [OnboardingFeatureRow.Model]
        let headlineFont: Font
        let headlineColor: Color
        let headlineAccentColor: Color
        let headlineLineSpacing: CGFloat
        let topRuleColor: Color
        let ruleHeight: CGFloat
        let kickerBottomPadding: CGFloat
        let topRuleTopPadding: CGFloat
    }
}

extension OnboardingValueView.Model {
    init(ds: DesignSystem = .standard) {
        self.kicker = OnboardingKicker.Model(text: AppStrings.Onboarding.valueKicker, ds: ds)
        self.headlineLine1 = AppStrings.Onboarding.valueHeadlineLine1
        self.headlineLine2 = AppStrings.Onboarding.valueHeadlineLine2
        self.rows = [
            OnboardingFeatureRow.Model(
                id: "brief",
                icon: "sparkles",
                kicker: AppStrings.Onboarding.valueBriefKicker,
                title: AppStrings.Onboarding.valueBriefTitle,
                body: AppStrings.Onboarding.valueBriefBody,
                ds: ds
            ),
            OnboardingFeatureRow.Model(
                id: "notebooks",
                icon: "book.closed",
                kicker: AppStrings.Onboarding.valueNotebooksKicker,
                title: AppStrings.Onboarding.valueNotebooksTitle,
                body: AppStrings.Onboarding.valueNotebooksBody,
                ds: ds
            ),
            OnboardingFeatureRow.Model(
                id: "search",
                icon: "magnifyingglass",
                kicker: AppStrings.Onboarding.valueSearchKicker,
                title: AppStrings.Onboarding.valueSearchTitle,
                body: AppStrings.Onboarding.valueSearchBody,
                isLast: true,
                ds: ds
            )
        ]
        self.headlineFont = .system(.largeTitle, design: .serif).weight(.light)
        self.headlineColor = ds.colors.ink
        self.headlineAccentColor = ds.colors.ink2
        self.headlineLineSpacing = ds.spacing.xs
        self.topRuleColor = ds.colors.rule
        self.ruleHeight = ds.layout.borderWidth
        self.kickerBottomPadding = ds.spacing.md
        self.topRuleTopPadding = ds.spacing.lg
    }
}
