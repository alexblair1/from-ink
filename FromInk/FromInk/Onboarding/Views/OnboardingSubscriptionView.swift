import SwiftUI

/// Subscription screen — paywall with three vertically-stacked tier
/// options and a reactive headline that changes based on the
/// selected tier.
///
/// Per subscription EDD §5 (revised), all three tiers render as
/// equal-weight cards stacked in a list. The brand position lives in
/// the headline + body above the cards, which update based on which
/// tier is currently selected:
///
///     LIFETIME selected →  "Pay once. Yours, forever."
///                          "From Ink, and every update we'll ever ship."
///                          "Yours, on every device you'll ever own."
///                          "No subscription."
///     YEARLY selected   →  "Free for 7 days, then $14.99 a year."
///                          "Cancel anytime."
///     MONTHLY selected  →  "Free for 7 days, then $2.99 a month."
///                          "Cancel anytime."
///
/// Headline and body change at the same instant the tier selection
/// changes. The cards below are visually equal (same component, same
/// width, same spacing); the editorial layer above carries each tier's
/// specific framing.
///
/// Feature list below the tier section is shared across all tiers —
/// every paid customer gets the same From Ink Plus feature set,
/// regardless of which payment cadence they choose.
///
struct OnboardingSubscriptionView: View {
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
                // Transitions when the selected tier changes so the
                // headline + body swap feels intentional rather than
                // janky.
                .animation(model.headlineAnimation, value: model.headlineLine1)

            // Body — one or more sentences stacked vertically. Lifetime
            // shows three lines (updates promise, devices promise, "No
            // subscription." punch); yearly and monthly show a single
            // "Cancel anytime." line. The VStack animates the count
            // change when selection moves between tiers.
            VStack(alignment: .leading, spacing: model.bodyParagraphSpacing) {
                ForEach(model.bodyLines, id: \.self) { line in
                    Text(line)
                        .font(model.bodyFont)
                        .foregroundStyle(model.bodyColor)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(model.bodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, model.bodyTopPadding)
            .animation(model.headlineAnimation, value: model.bodyLines)

            Rectangle()
                .fill(model.topRuleColor)
                .frame(height: model.ruleHeight)
                .padding(.top, model.tierRuleTopPadding)

            // Three tier cards stacked vertically, equal width, equal
            // visual weight. Selection state communicated by each
            // card's internal border + background tint + indicator dot.
            VStack(spacing: model.tierCardSpacing) {
                OnboardingTierCard(model: model.lifetimeCard)
                OnboardingTierCard(model: model.yearlyCard)
                OnboardingTierCard(model: model.monthlyCard)
            }
            .padding(.top, model.tierStackTopPadding)

            // Feature list — same 9 rows regardless of selected tier.
            // The tiers differ in payment cadence; the feature set is
            // identical, including Family Sharing (subscription EDD §2.1).
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
        let bodyLines: [String]
        let lifetimeCard: OnboardingTierCard.Model
        let yearlyCard: OnboardingTierCard.Model
        let monthlyCard: OnboardingTierCard.Model
        let rows: [OnboardingIncludedRow.Model]
        let headlineFont: Font
        let headlineColor: Color
        let headlineAccentColor: Color
        let headlineLineSpacing: CGFloat
        let headlineAnimation: Animation
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let bodyParagraphSpacing: CGFloat
        let topRuleColor: Color
        let ruleHeight: CGFloat
        let kickerBottomPadding: CGFloat
        let bodyTopPadding: CGFloat
        let tierRuleTopPadding: CGFloat
        let tierStackTopPadding: CGFloat
        let tierCardSpacing: CGFloat
        let rowsTopPadding: CGFloat
    }
}

extension OnboardingSubscriptionView.Model {
    init(
        selectedTier: SubscriptionTier,
        onTierSelected: @escaping (SubscriptionTier) -> Void,
        ds: DesignSystem = .standard
    ) {
        self.kicker = OnboardingKicker.Model(text: AppStrings.Onboarding.subscriptionKicker, ds: ds)

        // Headline + body switch based on selected tier. The view
        // animates the swap via `.animation(value: headlineLine1)` for
        // the headline and `.animation(value: bodyLines)` for the body.
        let copy = Self.copy(for: selectedTier)
        self.headlineLine1 = copy.headlineLine1
        self.headlineLine2 = copy.headlineLine2
        self.bodyLines = copy.bodyLines

        // Three stacked tier cards. Each gets its own selection state.
        // Lifetime carries a "pay once" subtitle to distinguish it from
        // the per-period tiers; yearly and monthly carry the cadence
        // directly in the price string so no subtitle is needed.
        self.lifetimeCard = OnboardingTierCard.Model(
            kicker: AppStrings.Onboarding.subscriptionLifetimeKicker,
            price: AppStrings.Onboarding.subscriptionLifetimePriceMajor,
            subtitle: AppStrings.Onboarding.subscriptionLifetimePriceCaption,
            isSelected: selectedTier == .lifetime,
            onTap: { onTierSelected(.lifetime) },
            ds: ds
        )
        self.yearlyCard = OnboardingTierCard.Model(
            kicker: AppStrings.Onboarding.subscriptionYearlyKicker,
            price: AppStrings.Onboarding.subscriptionYearlyPrice,
            subtitle: nil,
            isSelected: selectedTier == .yearly,
            onTap: { onTierSelected(.yearly) },
            ds: ds
        )
        self.monthlyCard = OnboardingTierCard.Model(
            kicker: AppStrings.Onboarding.subscriptionMonthlyKicker,
            price: AppStrings.Onboarding.subscriptionMonthlyPrice,
            subtitle: nil,
            isSelected: selectedTier == .monthly,
            onTap: { onTierSelected(.monthly) },
            ds: ds
        )

        // Nine feature rows — eight from the original spec plus Family
        // Sharing (subscription EDD §2.1 — applies to all three tiers,
        // belongs in the included-features list rather than as a badge
        // inside any one tier card).
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
            ),
            OnboardingIncludedRow.Model(
                id: "family",
                icon: "person.2",
                text: AppStrings.Onboarding.subscriptionFeatureFamilySharing,
                ds: ds
            )
        ]

        self.headlineFont = .system(.largeTitle, design: .serif).weight(.light)
        self.headlineColor = ds.colors.ink
        self.headlineAccentColor = ds.colors.ink2
        self.headlineLineSpacing = ds.spacing.xs
        self.headlineAnimation = ds.animation.standard
        self.bodyFont = .system(.subheadline, design: .default)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.xxs
        self.bodyParagraphSpacing = ds.spacing.sm
        self.topRuleColor = ds.colors.rule
        self.ruleHeight = ds.layout.borderWidth
        self.kickerBottomPadding = ds.spacing.md
        self.bodyTopPadding = ds.spacing.md
        self.tierRuleTopPadding = ds.spacing.lg
        self.tierStackTopPadding = ds.spacing.lg
        self.tierCardSpacing = ds.spacing.md
        self.rowsTopPadding = ds.spacing.lg
    }

    /// Headline + body copy for the currently-selected tier. Each tier
    /// has its own framing: lifetime carries the ownership commitment  
    /// across three lines (updates promise, devices promise, "No
    /// subscription." punch); the subscription tiers lead with the
    /// trial offer + cadence and close with a single reassurance line.
    private static func copy(for tier: SubscriptionTier) -> (headlineLine1: String, headlineLine2: String, bodyLines: [String]) {
        switch tier {
        case .lifetime:
            return (
                headlineLine1: AppStrings.Onboarding.subscriptionLifetimeHeadlineLine1,
                headlineLine2: AppStrings.Onboarding.subscriptionLifetimeHeadlineLine2,
                bodyLines: [
                    AppStrings.Onboarding.subscriptionLifetimeBody1,
                    AppStrings.Onboarding.subscriptionLifetimeBody2,
                    AppStrings.Onboarding.subscriptionLifetimeBody3
                ]
            )
        case .yearly:
            return (
                headlineLine1: AppStrings.Onboarding.subscriptionYearlyHeadlineLine1,
                headlineLine2: AppStrings.Onboarding.subscriptionYearlyHeadlineLine2,
                bodyLines: [AppStrings.Onboarding.subscriptionYearlyBody]
            )
        case .monthly:
            return (
                headlineLine1: AppStrings.Onboarding.subscriptionMonthlyHeadlineLine1,
                headlineLine2: AppStrings.Onboarding.subscriptionMonthlyHeadlineLine2,
                bodyLines: [AppStrings.Onboarding.subscriptionMonthlyBody]
            )
        }
    }
}
