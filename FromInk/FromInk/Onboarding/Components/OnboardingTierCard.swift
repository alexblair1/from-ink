import SwiftUI

/// Compact tier card used for the yearly and monthly subscription
/// options on the paywall. Visually paired with another instance of
/// itself in an HStack below the lifetime hero card, so the two
/// subscription options read as alternatives to the lifetime brand
/// position rather than peer choices to it.
///
///     ┌──────────────────┐
///     │  YEARLY      ●   │  ← kicker + selection indicator
///     │                  │
///     │  $14.99/yr       │  ← medium serif price
///     │  ABOUT $1.25/MO  │  ← optional small mono subtitle
///     └──────────────────┘
///
/// Selection state communicated by:
/// - background tint: paper (unselected) vs surface (selected)
/// - border weight: 1pt rule (unselected) vs 1.5pt ink (selected)
/// - small filled-vs-hollow dot in the top-right
///
/// Same tap-to-select behavior as `OnboardingLifetimeCard`. The two
/// component types share visual register but differ in size — the
/// lifetime card commits to a hero treatment, the tier card stays
/// compact.
///
struct OnboardingTierCard: View {
    let model: Model

    @ScaledMetric(relativeTo: .title) private var priceSize: CGFloat = 24

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(model.kicker)
                        .font(model.kickerFont)
                        .tracking(model.kickerTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(model.kickerColor)
                    Spacer(minLength: 0)
                    selectionIndicator
                }
                .padding(.bottom, model.headerBottomPadding)

                Text(model.price)
                    .font(.system(size: priceSize, weight: .light, design: .serif))
                    .foregroundStyle(model.priceColor)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(model.subtitleFont)
                        .tracking(model.subtitleTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(model.subtitleColor)
                        .padding(.top, model.subtitleTopPadding)
                }
            }
            .padding(model.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
                    .strokeBorder(model.borderColor, lineWidth: model.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
            .animation(model.selectionAnimation, value: model.isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.isSelected ? model.accessibilitySelected : model.accessibilityNotSelected)
        .accessibilityHint(model.accessibilityHint)
        .accessibilityAddTraits(model.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionIndicator: some View {
        Group {
            if model.isSelected {
                Circle()
                    .fill(model.indicatorActiveColor)
                    .frame(width: model.indicatorSize, height: model.indicatorSize)
            } else {
                Circle()
                    .strokeBorder(model.indicatorInactiveColor, lineWidth: model.indicatorBorderWidth)
                    .frame(width: model.indicatorSize, height: model.indicatorSize)
            }
        }
    }
}

extension OnboardingTierCard {
    struct Model {
        let kicker: String
        let price: String
        let subtitle: String?
        let isSelected: Bool
        let onTap: () -> Void
        // Typography
        let kickerFont: Font
        let kickerColor: Color
        let kickerTracking: CGFloat
        let priceColor: Color
        let subtitleFont: Font
        let subtitleColor: Color
        let subtitleTracking: CGFloat
        // Layout
        let cardPadding: CGFloat
        let cornerRadius: CGFloat
        let cardBackground: Color
        let borderColor: Color
        let borderWidth: CGFloat
        let headerBottomPadding: CGFloat
        let subtitleTopPadding: CGFloat
        // Selection indicator
        let indicatorSize: CGFloat
        let indicatorBorderWidth: CGFloat
        let indicatorActiveColor: Color
        let indicatorInactiveColor: Color
        let selectionAnimation: Animation
        // Accessibility
        let accessibilityLabel: String
        let accessibilitySelected: String
        let accessibilityNotSelected: String
        let accessibilityHint: String
    }
}

extension OnboardingTierCard.Model {
    init(
        kicker: String,
        price: String,
        subtitle: String?,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.kicker = kicker
        self.price = price
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.onTap = onTap

        self.kickerFont = ds.typography.onboardingKicker
        self.kickerColor = ds.colors.ink2
        self.kickerTracking = ds.typography.kickerTracking
        self.priceColor = ds.colors.ink
        self.subtitleFont = ds.typography.onboardingKicker
        self.subtitleColor = ds.colors.ink3
        self.subtitleTracking = ds.typography.monoLinkTracking

        self.cardPadding = ds.spacing.base
        self.cornerRadius = ds.cornerRadius.sheet
        self.cardBackground = isSelected ? ds.colors.surface : ds.colors.paper
        self.borderColor = isSelected ? ds.colors.ink : ds.colors.rule
        self.borderWidth = isSelected ? 1.5 : ds.layout.borderWidth
        self.headerBottomPadding = ds.spacing.sm
        self.subtitleTopPadding = ds.spacing.xs

        self.indicatorSize = 10
        self.indicatorBorderWidth = 1.5
        self.indicatorActiveColor = ds.colors.ink
        self.indicatorInactiveColor = ds.colors.ink3
        self.selectionAnimation = ds.animation.fast

        if let subtitle {
            self.accessibilityLabel = "\(kicker), \(price), \(subtitle)."
        } else {
            self.accessibilityLabel = "\(kicker), \(price)."
        }
        self.accessibilitySelected = NSLocalizedString(
            "onboarding.tier.value.selected",
            value: "Selected",
            comment: "VoiceOver value when a tier card is currently selected on the paywall."
        )
        self.accessibilityNotSelected = NSLocalizedString(
            "onboarding.tier.value.not_selected",
            value: "Not selected",
            comment: "VoiceOver value when a tier card is not currently selected on the paywall."
        )
        self.accessibilityHint = NSLocalizedString(
            "onboarding.tier.hint",
            value: "Tap to select this purchase option.",
            comment: "VoiceOver hint when the user can tap to select a different tier on the paywall."
        )
    }
}
