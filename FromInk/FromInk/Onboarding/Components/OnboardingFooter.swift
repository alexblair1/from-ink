import SwiftUI

/// Persistent footer that lives below the swipeable content area.
/// The primary button is structurally fixed at the same tree position
/// across every step — only its label and action change. SwiftUI keeps
/// it as the same view identity so it doesn't regenerate as the user
/// moves through the flow.
///
/// Below the button is a zone for the optional secondary link and
/// footer note. The zone uses `minHeight` so the button position is
/// consistent across screens at default Dynamic Type, but the zone
/// can grow at accessibility text sizes when the mono uppercase
/// secondary + note exceed the default reserved height.
///
struct OnboardingFooter: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPrimaryButton(model: model.primary)

            // App Store-required legal chrome (Restore / Privacy / Terms).
            // Rendered only when supplied — subscription only. Lives
            // directly under the CTA per convention; the slight CTA Y
            // shift on subscription is the trade-off for compliant
            // placement of these affordances.
            if let legal = model.legalChrome {
                OnboardingLegalChrome(model: legal)
                    .padding(.top, model.legalChromeTopPadding)
            }

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
        /// App Store legal/restore chrome — rendered under the primary
        /// CTA when present. Subscription only.
        let legalChrome: OnboardingLegalChrome.Model?
        let secondarySpacing: CGFloat
        let secondaryZoneHeight: CGFloat
        let secondaryZoneTopPadding: CGFloat
        let legalChromeTopPadding: CGFloat
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
        self.legalChromeTopPadding = ds.spacing.base
    }
}
