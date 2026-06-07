import SwiftUI

/// Microphone permission card under the calendar / reminders rows. Now
/// fully interactive — taps either request system access
/// (`.notDetermined`) or open Settings (`.granted` to revoke, `.denied`
/// to grant). Visually still a surface-tinted card to mark it as
/// optional / future-feature (voice notes), distinct from the
/// always-essential calendar / reminders rows above.
///
/// Right-side affordance mirrors the OnboardingPermissionRow pattern:
/// `OPEN SETTINGS →` when `.denied`, a small checkmark when `.granted`,
/// chevron when `.notDetermined` (the row is actionable).
///
struct OnboardingMicrophoneCard: View {
    let model: Model

    var body: some View {
        Button(action: model.action) {
            HStack(alignment: .center, spacing: model.iconSpacing) {
                Image(systemName: model.icon)
                    .font(model.iconFont)
                    .foregroundStyle(model.iconColor)
                    .symbolRenderingMode(.monochrome)
                    .frame(minWidth: model.iconMinWidth, alignment: .leading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: model.textSpacing) {
                    Text(model.kicker)
                        .font(model.kickerFont)
                        .tracking(model.kickerTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(model.kickerColor)
                    Text(model.body)
                        .font(model.bodyFont)
                        .foregroundStyle(model.bodyColor)
                        .lineSpacing(model.bodyLineSpacing)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                rightAffordance
            }
            .padding(model.cardPadding)
            .background(model.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.kicker)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var rightAffordance: some View {
        switch model.status {
        case .denied:
            HStack(spacing: model.openSettingsArrowSpacing) {
                Text(model.openSettingsLabel)
                    .font(model.openSettingsFont)
                    .tracking(model.openSettingsTracking)
                    .textCase(.uppercase)
                Text(verbatim: "→")
                    .font(model.openSettingsArrowFont)
            }
            .foregroundStyle(model.openSettingsColor)
            .fixedSize(horizontal: true, vertical: false)
        case .granted:
            Image(systemName: model.grantedIcon)
                .font(model.chevronFont)
                .foregroundStyle(model.grantedColor)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)
        case .notDetermined:
            Image(systemName: model.chevron)
                .font(model.chevronFont)
                .foregroundStyle(model.chevronColor)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityValue: String {
        switch model.status {
        case .notDetermined: return model.valueNotDetermined
        case .granted:       return model.valueGranted
        case .denied:        return model.valueDenied
        }
    }

    private var accessibilityHint: String {
        switch model.status {
        case .notDetermined: return model.hintRequestsAccess
        case .granted, .denied: return model.hintOpensSettings
        }
    }
}

extension OnboardingMicrophoneCard {
    struct Model {
        let icon: String
        let chevron: String
        let grantedIcon: String
        let kicker: String
        let body: String
        let status: MicrophoneAuthStatus
        let iconFont: Font
        let iconColor: Color
        let iconMinWidth: CGFloat
        let iconSpacing: CGFloat
        let textSpacing: CGFloat
        let kickerFont: Font
        let kickerColor: Color
        let kickerTracking: CGFloat
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let chevronFont: Font
        let chevronColor: Color
        let grantedColor: Color
        let cardBackground: Color
        let cardPadding: CGFloat
        let cornerRadius: CGFloat
        // Open Settings inline affordance
        let openSettingsLabel: String
        let openSettingsFont: Font
        let openSettingsArrowFont: Font
        let openSettingsArrowSpacing: CGFloat
        let openSettingsTracking: CGFloat
        let openSettingsColor: Color
        // Accessibility values
        let valueNotDetermined: String
        let valueGranted: String
        let valueDenied: String
        let hintRequestsAccess: String
        let hintOpensSettings: String
        let action: () -> Void
    }
}

extension OnboardingMicrophoneCard.Model {
    init(
        kicker: String,
        body: String,
        status: MicrophoneAuthStatus,
        action: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.icon = "mic"
        self.chevron = "chevron.forward"
        self.grantedIcon = "checkmark"
        self.kicker = kicker
        self.body = body
        self.status = status
        self.iconFont = .system(.title2, design: .default)
        self.iconColor = ds.colors.ink2
        self.iconMinWidth = ds.layout.onboardingPermissionRowIconColumn
        self.iconSpacing = ds.spacing.base
        self.textSpacing = ds.spacing.xs
        self.kickerFont = ds.typography.onboardingKicker
        self.kickerColor = ds.colors.ink2
        self.kickerTracking = ds.typography.monoLinkTracking
        self.bodyFont = .system(.footnote, design: .default)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.xxs
        self.chevronFont = .system(.footnote, design: .default)
        self.chevronColor = ds.colors.ink3
        self.grantedColor = ds.colors.ink
        self.cardBackground = ds.colors.surface
        self.cardPadding = ds.spacing.base
        self.cornerRadius = ds.cornerRadius.sheet

        self.openSettingsLabel = AppStrings.Onboarding.permissionsOpenSettings
        self.openSettingsFont = ds.typography.onboardingTextLink
        self.openSettingsArrowFont = .system(.footnote, design: .serif).weight(.light).italic()
        self.openSettingsArrowSpacing = ds.spacing.xs
        self.openSettingsTracking = ds.typography.monoLinkTracking
        self.openSettingsColor = ds.colors.ink

        self.valueNotDetermined = NSLocalizedString(
            "onboarding.microphone.value.not_determined",
            value: "Off",
            comment: "VoiceOver value when microphone access hasn't been asked yet."
        )
        self.valueGranted = NSLocalizedString(
            "onboarding.microphone.value.granted",
            value: "On",
            comment: "VoiceOver value when microphone access has been granted."
        )
        self.valueDenied = NSLocalizedString(
            "onboarding.microphone.value.denied",
            value: "Off, opens Settings",
            comment: "VoiceOver value when microphone access was denied."
        )
        self.hintRequestsAccess = NSLocalizedString(
            "onboarding.microphone.hint.requests",
            value: "Tap to grant access.",
            comment: "VoiceOver hint when the microphone card will trigger the system prompt."
        )
        self.hintOpensSettings = NSLocalizedString(
            "onboarding.microphone.hint.settings",
            value: "Tap to open Settings.",
            comment: "VoiceOver hint when the microphone card will route to the Settings app."
        )

        self.action = action
    }
}
