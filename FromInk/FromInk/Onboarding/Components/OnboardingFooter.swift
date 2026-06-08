import SwiftUI

/// Persistent footer that lives below the swipeable content area.
/// The primary button is structurally fixed at the same tree position
/// across every step — only its label and action change. SwiftUI keeps
/// it as the same view identity so it doesn't regenerate as the user
/// moves through the flow.
///
/// **CTA Y-position invariant — and why legal chrome lives ABOVE the
/// CTA, not below.** The footer is anchored to the screen's bottom
/// edge (via the container's `footerBottomPadding`). Anything rendered
/// *below* the CTA inside this footer pushes the CTA *up* relative to
/// the screen bottom — so a step-conditional chrome below the CTA
/// shifts the CTA's Y position between steps. Rendering chrome
/// *above* the CTA instead keeps the CTA pinned to the footer's
/// bottom edge regardless of what sits above it: the footer's TOP
/// grows when chrome is present, but the CTA's BOTTOM (and thus its
/// screen Y) stays put. This file therefore renders legal chrome
/// *before* the primary button in tree order.
///
/// Below the button is a zone for the optional secondary link and
/// footer note. The zone uses `minHeight` so the button position is
/// consistent across screens at default Dynamic Type, but the zone
/// can grow at accessibility text sizes when the mono uppercase
/// secondary + note exceed the default reserved height. Same rule:
/// because the zone is BELOW the CTA, anything rendered there does
/// push the CTA up — so the secondary slot is reserved-height even
/// when empty.
///
struct OnboardingFooter: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            // App Store-required legal chrome (Restore / Privacy /
            // Terms). Rendered ABOVE the CTA — its presence on the
            // subscription step adds height to the top of the footer
            // without shifting the CTA's bottom-anchored Y position.
            // Subscription only; nil on welcome / value / permissions.
            if let legal = model.legalChrome {
                OnboardingLegalChrome(model: legal)
                    .padding(.bottom, model.legalChromeBottomPadding)
            }

            OnboardingPrimaryButton(model: model.primary)

            // Secondary zone is rendered ONLY when there is content to put
            // in it. With no current screen using a secondary link or
            // footer note (subscription's dismiss is the corner X close
            // button; permissions' opt-out is the confirmation alert), the
            // zone collapses and the primary CTA's bottom edge sits at the
            // container's `footerBottomPadding` from the screen bottom.
            if model.secondary != nil || model.note != nil {
                VStack(spacing: model.secondarySpacing) {
                    if let secondary = model.secondary {
                        OnboardingSecondaryLink(model: secondary)
                    }
                    if let note = model.note {
                        OnboardingFooterNote(model: note)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: model.secondaryZoneHeight)
                .padding(.top, model.secondaryZoneTopPadding)
            }
        }
    }
}

extension OnboardingFooter {
    struct Model {
        let primary: OnboardingPrimaryButton.Model
        let secondary: OnboardingSecondaryLink.Model?
        let note: OnboardingFooterNote.Model?
        /// App Store legal/restore chrome rendered ABOVE the primary
        /// CTA when present. Subscription only. nil on every other
        /// step. Placement-above is load-bearing — see the file
        /// header for the CTA Y-position invariant.
        let legalChrome: OnboardingLegalChrome.Model?
        let secondarySpacing: CGFloat
        let secondaryZoneHeight: CGFloat
        let secondaryZoneTopPadding: CGFloat
        let legalChromeBottomPadding: CGFloat
    }
}

extension OnboardingFooter.Model {
    init(
        primary: OnboardingPrimaryButton.Model,
        secondary: OnboardingSecondaryLink.Model? = nil,
        note: OnboardingFooterNote.Model? = nil,
        legalChrome: OnboardingLegalChrome.Model? = nil,
        ds: DesignSystem = .standard
    ) {
        self.primary = primary
        self.secondary = secondary
        self.note = note
        self.legalChrome = legalChrome
        self.secondarySpacing = ds.spacing.xs
        self.secondaryZoneHeight = ds.spacing.xxl
        self.secondaryZoneTopPadding = ds.spacing.xs
        self.legalChromeBottomPadding = ds.spacing.base
    }
}
