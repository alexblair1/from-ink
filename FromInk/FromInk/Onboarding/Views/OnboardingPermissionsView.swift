import SwiftUI

/// Permissions screen — kicker, two-tone headline, body, two toggle rows,
/// then the informational microphone card.
///
/// The headline flows as one block of text (no hardcoded break) so long
/// localizations and Dynamic Type both wrap naturally. All text uses
/// system text styles.
///
/// Swipe is disabled on this screen by the container — the user must tap
/// either the primary "Continue" button or the secondary "Not now" link
/// to leave this step in either direction.
///
struct OnboardingPermissionsView: View {
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
                .padding(.top, model.topRuleTopPadding)

            OnboardingPermissionRow(model: model.calendarRow)
            OnboardingPermissionRow(model: model.remindersRow)
            OnboardingPermissionRow(model: model.locationRow)

            OnboardingMicrophoneCard(model: model.microphoneCard)
                .padding(.top, model.microphoneCardTopPadding)
        }
    }
}

extension OnboardingPermissionsView {
    struct Model {
        let kicker: OnboardingKicker.Model
        let headlineLine1: String
        let headlineLine2: String
        let body: String
        let calendarRow: OnboardingPermissionRow.Model
        let remindersRow: OnboardingPermissionRow.Model
        let locationRow: OnboardingPermissionRow.Model
        let microphoneCard: OnboardingMicrophoneCard.Model
        let headlineFont: Font
        let headlineColor: Color
        let headlineAccentColor: Color
        let headlineLineSpacing: CGFloat
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let topRuleColor: Color
        let ruleHeight: CGFloat
        let kickerBottomPadding: CGFloat
        let bodyTopPadding: CGFloat
        let topRuleTopPadding: CGFloat
        let microphoneCardTopPadding: CGFloat
    }
}

extension OnboardingPermissionsView.Model {
    init(
        calendarStatus: PermissionAuthStatus,
        remindersStatus: PermissionAuthStatus,
        locationStatus: LocationAuthStatus,
        microphoneStatus: MicrophoneAuthStatus,
        onCalendarTap: @escaping () -> Void,
        onRemindersTap: @escaping () -> Void,
        onLocationTap: @escaping () -> Void,
        onMicrophoneTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.kicker = OnboardingKicker.Model(text: AppStrings.Onboarding.permissionsKicker, ds: ds)
        self.headlineLine1 = AppStrings.Onboarding.permissionsHeadlineLine1
        self.headlineLine2 = AppStrings.Onboarding.permissionsHeadlineLine2
        self.body = AppStrings.Onboarding.permissionsBody

        self.calendarRow = OnboardingPermissionRow.Model(
            icon: "calendar",
            title: AppStrings.Onboarding.permissionsCalendarTitle,
            body: AppStrings.Onboarding.permissionsCalendarBody,
            status: calendarStatus,
            action: onCalendarTap,
            ds: ds
        )
        self.remindersRow = OnboardingPermissionRow.Model(
            icon: "checklist",
            title: AppStrings.Onboarding.permissionsRemindersTitle,
            body: AppStrings.Onboarding.permissionsRemindersBody,
            status: remindersStatus,
            action: onRemindersTap,
            ds: ds
        )
        self.locationRow = OnboardingPermissionRow.Model(
            icon: "location",
            title: AppStrings.Onboarding.permissionsLocationTitle,
            body: AppStrings.Onboarding.permissionsLocationBody,
            status: locationStatus,
            action: onLocationTap,
            ds: ds
        )
        self.microphoneCard = OnboardingMicrophoneCard.Model(
            kicker: AppStrings.Onboarding.permissionsMicrophoneKicker,
            body: AppStrings.Onboarding.permissionsMicrophoneBody,
            status: microphoneStatus,
            action: onMicrophoneTap,
            ds: ds
        )

        self.headlineFont = .system(.largeTitle, design: .serif).weight(.light)
        self.headlineColor = ds.colors.ink
        self.headlineAccentColor = ds.colors.ink2
        self.headlineLineSpacing = ds.spacing.xs
        self.bodyFont = .system(.subheadline, design: .default)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.xs
        self.topRuleColor = ds.colors.rule
        self.ruleHeight = ds.layout.borderWidth
        self.kickerBottomPadding = ds.spacing.md
        self.bodyTopPadding = ds.spacing.md
        self.topRuleTopPadding = ds.spacing.lg
        self.microphoneCardTopPadding = ds.spacing.base
    }
}
