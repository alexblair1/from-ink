import SwiftUI

/// Value screen ("The idea") — kicker, two-tone headline ("From ink"
/// + italic "to done."), five feature rows separated by hairline rules.
///
/// The five rows form a deliberate escalation:
///
///     1. Ink & text         — how you write
///     2. Daily brief        — what you see each morning
///     3. Connections        — where it goes
///     4. For every reader   — who can use it
///     5. Privacy            — who can see it
///
/// Privacy is the final row by design: the user leaves this screen on
/// the boundary that protects them, right before the Continue button.
///
/// The headline is composed of two localized strings concatenated with
/// a single space and styled as one continuous flowing block — no
/// hardcoded `\n`. It wraps based on available width, so long-locale
/// translations and large Dynamic Type sizes both reflow gracefully.
/// All text uses system text styles (Dynamic Type-aware). At AX5 the
/// rows overflow the page and the per-page vertical ScrollView in
/// OnboardingContainerView handles the scroll.
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
                id: "ink-text",
                icon: "pencil.and.scribble",
                kicker: AppStrings.Onboarding.valueInkTextKicker,
                title: AppStrings.Onboarding.valueInkTextTitle,
                body: AppStrings.Onboarding.valueInkTextBody,
                ds: ds
            ),
            OnboardingFeatureRow.Model(
                id: "brief",
                icon: "newspaper",
                kicker: AppStrings.Onboarding.valueBriefKicker,
                title: AppStrings.Onboarding.valueBriefTitle,
                body: AppStrings.Onboarding.valueBriefBody,
                ds: ds
            ),
            OnboardingFeatureRow.Model(
                id: "connections",
                icon: "paperplane",
                kicker: AppStrings.Onboarding.valueConnectionsKicker,
                title: AppStrings.Onboarding.valueConnectionsTitle,
                body: AppStrings.Onboarding.valueConnectionsBody,
                ds: ds
            ),
            OnboardingFeatureRow.Model(
                id: "reading",
                icon: "textformat.size",
                kicker: AppStrings.Onboarding.valueReadingKicker,
                title: AppStrings.Onboarding.valueReadingTitle,
                body: AppStrings.Onboarding.valueReadingBody,
                ds: ds
            ),
            OnboardingFeatureRow.Model(
                id: "privacy",
                icon: "lock",
                kicker: AppStrings.Onboarding.valuePrivacyKicker,
                title: AppStrings.Onboarding.valuePrivacyTitle,
                body: AppStrings.Onboarding.valuePrivacyBody,
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
