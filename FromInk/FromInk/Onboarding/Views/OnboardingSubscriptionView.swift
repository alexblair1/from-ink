import SwiftUI

/// Subscription screen — kicker, two-tone headline, body, price block,
/// then three "included" rows.
///
/// The headline flows as one block (no hardcoded break) and uses
/// `.largeTitle` so it scales with Dynamic Type. The price major value
/// uses `@ScaledMetric` anchored to `.largeTitle` so the design's
/// 52pt hero numeric is preserved at default text size and grows with
/// the system text scale. Other typography uses system text styles.
///
struct OnboardingSubscriptionView: View {
    let model: Model

    @ScaledMetric(relativeTo: .largeTitle) private var priceMajorSize: CGFloat = 52

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

            Text(model.body)
                .font(model.bodyFont)
                .foregroundStyle(model.bodyColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(model.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, model.bodyTopPadding)

            Rectangle()
                .fill(model.topRuleColor)
                .frame(height: model.ruleHeight)
                .padding(.top, model.priceRuleTopPadding)

            HStack(alignment: .firstTextBaseline, spacing: model.priceUnitSpacing) {
                Text(model.priceMajor)
                    .font(.system(size: priceMajorSize, weight: .light, design: .serif))
                    .foregroundStyle(model.priceMajorColor)
                Text(model.priceUnit)
                    .font(model.priceUnitFont)
                    .foregroundStyle(model.priceUnitColor)
            }
            .padding(.top, model.priceTopPadding)
            .accessibilityElement(children: .combine)

            Text(model.priceCaption)
                .font(model.priceCaptionFont)
                .tracking(model.priceCaptionTracking)
                .textCase(.uppercase)
                .foregroundStyle(model.priceCaptionColor)
                .padding(.top, model.priceCaptionTopPadding)

            // Consumer-friendly per-month breakdown — reframes the
            // sticker price from "annual hit" to "coffee a month."
            Text(model.priceMonthly)
                .font(model.priceMonthlyFont)
                .foregroundStyle(model.priceMonthlyColor)
                .padding(.top, model.priceMonthlyTopPadding)

            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    OnboardingIncludedRow(model: row)
                }
            }
            .padding(.top, model.rowsTopPadding)
        }
    }
}

extension OnboardingSubscriptionView {
    struct Model {
        let kicker: OnboardingKicker.Model
        let headlineLine1: String
        let headlineLine2: String
        let body: String
        let priceMajor: String
        let priceUnit: String
        let priceCaption: String
        let priceMonthly: String
        let rows: [OnboardingIncludedRow.Model]
        let headlineFont: Font
        let headlineColor: Color
        let headlineAccentColor: Color
        let headlineLineSpacing: CGFloat
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let topRuleColor: Color
        let ruleHeight: CGFloat
        let priceUnitSpacing: CGFloat
        let priceMajorColor: Color
        let priceUnitFont: Font
        let priceUnitColor: Color
        let priceCaptionFont: Font
        let priceCaptionTracking: CGFloat
        let priceCaptionColor: Color
        let priceMonthlyFont: Font
        let priceMonthlyColor: Color
        let kickerBottomPadding: CGFloat
        let bodyTopPadding: CGFloat
        let priceRuleTopPadding: CGFloat
        let priceTopPadding: CGFloat
        let priceCaptionTopPadding: CGFloat
        let priceMonthlyTopPadding: CGFloat
        let rowsTopPadding: CGFloat
    }
}

extension OnboardingSubscriptionView.Model {
    init(ds: DesignSystem = .standard) {
        self.kicker = OnboardingKicker.Model(text: AppStrings.Onboarding.subscriptionKicker, ds: ds)
        self.headlineLine1 = AppStrings.Onboarding.subscriptionHeadlineLine1
        self.headlineLine2 = AppStrings.Onboarding.subscriptionHeadlineLine2
        self.body = AppStrings.Onboarding.subscriptionBody
        self.priceMajor = AppStrings.Onboarding.subscriptionPriceMajor
        self.priceUnit = AppStrings.Onboarding.subscriptionPriceUnit
        self.priceCaption = AppStrings.Onboarding.subscriptionPriceCaption
        self.priceMonthly = AppStrings.Onboarding.subscriptionPriceMonthly
        // Per-feature icons (not generic checkmarks) — each row now
        // carries a meaningful SF Symbol so the list reads as a feature
        // gallery rather than a sameness loop. Borrowed from Goodnotes'
        // paywall pattern.
        self.rows = [
            OnboardingIncludedRow.Model(
                id: "notebooks",
                icon: "books.vertical",
                text: AppStrings.Onboarding.subscriptionFeatureNotebooks,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "writing",
                icon: "pencil.and.scribble",
                text: AppStrings.Onboarding.subscriptionFeatureWriting,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "handwriting",
                icon: "text.magnifyingglass",
                text: AppStrings.Onboarding.subscriptionFeatureHandwriting,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "brief",
                icon: "newspaper",
                text: AppStrings.Onboarding.subscriptionFeatureBrief,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "linking",
                icon: "calendar.badge.checkmark",
                text: AppStrings.Onboarding.subscriptionFeatureLinking,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "routing",
                icon: "paperplane",
                text: AppStrings.Onboarding.subscriptionFeatureRouting,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "pdfs",
                icon: "doc.text.magnifyingglass",
                text: AppStrings.Onboarding.subscriptionFeaturePDFs,
                ds: ds
            ),
            OnboardingIncludedRow.Model(
                id: "sync",
                icon: "icloud",
                text: AppStrings.Onboarding.subscriptionFeatureSync,
                ds: ds
            )
        ]
        self.headlineFont = .system(.largeTitle, design: .serif).weight(.light)
        self.headlineColor = ds.colors.ink
        self.headlineAccentColor = ds.colors.ink2
        self.headlineLineSpacing = ds.spacing.xs
        self.bodyFont = .system(.subheadline, design: .default)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.xs
        self.topRuleColor = ds.colors.rule
        self.ruleHeight = ds.layout.borderWidth
        self.priceUnitSpacing = ds.spacing.md
        self.priceMajorColor = ds.colors.ink
        self.priceUnitFont = .system(.title2, design: .serif).weight(.light).italic()
        self.priceUnitColor = ds.colors.ink2
        self.priceCaptionFont = ds.typography.onboardingKicker
        self.priceCaptionTracking = ds.typography.monoLinkTracking
        self.priceCaptionColor = ds.colors.ink2
        self.priceMonthlyFont = .system(.subheadline, design: .default)
        self.priceMonthlyColor = ds.colors.ink2
        self.kickerBottomPadding = ds.spacing.md
        self.bodyTopPadding = ds.spacing.md
        self.priceRuleTopPadding = ds.spacing.lg
        self.priceTopPadding = ds.spacing.base
        self.priceCaptionTopPadding = ds.spacing.sm
        self.priceMonthlyTopPadding = ds.spacing.xs
        self.rowsTopPadding = ds.spacing.base
    }
}
