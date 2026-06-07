import SwiftUI

/// App Store-required legal/restore link row rendered directly below the
/// primary CTA on the subscription screen. Three small mono uppercase
/// buttons: Restore (Purchases), Privacy, Terms.
///
/// Apple's HIG and App Store guidelines call for these affordances to
/// be easily accessible at the point of purchase — convention is the
/// row immediately under the subscribe button. (Borrowed visual pattern
/// from Goodnotes' paywall.)
///
/// Each button takes its own action so the wiring view can route to the
/// appropriate destination (StoreKit restore, privacy URL, terms URL).
/// Until the integration lands, the actions can be no-ops — the row's
/// only job here is to render the chrome.
///
struct OnboardingLegalChrome: View {
    let model: Model

    var body: some View {
        HStack(spacing: model.itemSpacing) {
            ForEach(model.items) { item in
                Button(action: item.action) {
                    Text(item.label)
                        .font(model.font)
                        .tracking(model.tracking)
                        .textCase(.uppercase)
                        .foregroundStyle(model.color)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension OnboardingLegalChrome {
    struct Model {
        let items: [Item]
        let itemSpacing: CGFloat
        let font: Font
        let tracking: CGFloat
        let color: Color
    }

    struct Item: Identifiable {
        let id: String
        let label: String
        let action: () -> Void
    }
}

extension OnboardingLegalChrome.Model {
    init(
        onRestore: @escaping () -> Void,
        onPrivacy: @escaping () -> Void,
        onTerms: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.items = [
            OnboardingLegalChrome.Item(
                id: "restore",
                label: AppStrings.Onboarding.subscriptionLegalRestore,
                action: onRestore
            ),
            OnboardingLegalChrome.Item(
                id: "privacy",
                label: AppStrings.Onboarding.subscriptionLegalPrivacy,
                action: onPrivacy
            ),
            OnboardingLegalChrome.Item(
                id: "terms",
                label: AppStrings.Onboarding.subscriptionLegalTerms,
                action: onTerms
            )
        ]
        self.itemSpacing = ds.spacing.lg
        self.font = ds.typography.onboardingTextLink
        self.tracking = ds.typography.monoLinkTracking
        self.color = ds.colors.ink2
    }
}
