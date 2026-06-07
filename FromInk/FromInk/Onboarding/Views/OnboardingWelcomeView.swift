import SwiftUI

/// Welcome screen — left-aligned, fills the page width inside the
/// container's horizontal padding.
///
///     [ink drop hero]
///     WELCOME TO
///     From Ink            (large serif italic wordmark, flows wide)
///     A quiet home for…   (serif lede, flows wide)
///
/// Hero typography (`brandIcon`, `wordmark`) uses `@ScaledMetric`
/// anchored to `.largeTitle` so the design's hero sizes are preserved
/// at default text size and grow with Dynamic Type. The lede never has
/// a hardcoded break — it wraps to fill available width, so long-locale
/// strings and large text both reflow gracefully.
///
struct OnboardingWelcomeView: View {
    let model: Model

    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var brandIconSize: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: model.brandIcon)
                .font(.system(size: brandIconSize, weight: .light))
                .foregroundStyle(model.brandIconColor)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)
                .padding(.bottom, model.iconBottomPadding)

            OnboardingKicker(model: model.kicker)
                .padding(.bottom, model.kickerBottomPadding)

            Text(model.wordmark)
                .font(.system(size: wordmarkSize, weight: .regular, design: .serif).italic())
                .foregroundStyle(model.wordmarkColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text(model.body)
                .font(model.bodyFont)
                .foregroundStyle(model.bodyColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(model.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, model.bodyTopPadding)
        }
    }
}

extension OnboardingWelcomeView {
    struct Model {
        let brandIcon: String
        let kicker: OnboardingKicker.Model
        let wordmark: String
        let body: String
        let brandIconColor: Color
        let wordmarkColor: Color
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let iconBottomPadding: CGFloat
        let kickerBottomPadding: CGFloat
        let bodyTopPadding: CGFloat
    }
}

extension OnboardingWelcomeView.Model {
    init(ds: DesignSystem = .standard) {
        self.brandIcon = "drop.halffull"
        self.kicker = OnboardingKicker.Model(text: AppStrings.Onboarding.welcomeKicker, ds: ds)
        self.wordmark = AppStrings.Onboarding.welcomeWordmark
        self.body = AppStrings.Onboarding.welcomeBody
        self.brandIconColor = ds.colors.ink
        self.wordmarkColor = ds.colors.ink
        self.bodyFont = .system(.title3, design: .serif).weight(.light)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.sm
        self.iconBottomPadding = ds.spacing.xl
        self.kickerBottomPadding = ds.spacing.base
        self.bodyTopPadding = ds.spacing.lg
    }
}
