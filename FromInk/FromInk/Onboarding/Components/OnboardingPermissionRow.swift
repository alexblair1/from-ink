import SwiftUI

/// One row in the permissions screen's grant list. The **entire row** is
/// the tap target — tap behavior depends on the row's current
/// authorization, which the Model expresses as two booleans:
/// `isGranted` (drives the switch's on/off visual) and
/// `requiresSettings` (when true, the switch is replaced with an
/// inline `OPEN SETTINGS →` link).
///
///     [icon]   Calendar & Events                      [switch | OPEN SETTINGS]
///              Show today's events at the top…
///
/// The Bool-based interface lets the same row handle any permission
/// type — EventKit (`PermissionAuthStatus`), Location
/// (`LocationAuthStatus`), or anything else — via typed init overloads
/// that translate the specific status enum into the boolean pair.
///
/// The icon column uses `minWidth` (not fixed `width`) so at large
/// Dynamic Type sizes the scaled SF Symbol glyph has room to grow
/// without spilling into the text column. All colors come from
/// `ds.colors.*` so the row reads correctly in both light and dark mode.
///
struct OnboardingPermissionRow: View {
    let model: Model

    var body: some View {
        Button(action: model.action) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: model.iconSpacing) {
                    Image(systemName: model.icon)
                        .font(model.iconFont)
                        .foregroundStyle(model.iconColor)
                        .symbolRenderingMode(.monochrome)
                        .frame(minWidth: model.iconMinWidth, alignment: .leading)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: model.textSpacing) {
                        Text(model.title)
                            .font(model.titleFont)
                            .foregroundStyle(model.titleColor)
                        Text(model.body)
                            .font(model.bodyFont)
                            .foregroundStyle(model.bodyColor)
                            .lineSpacing(model.bodyLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    rightAffordance
                }
                .padding(.vertical, model.rowVerticalPadding)

                Rectangle()
                    .fill(model.dividerColor)
                    .frame(height: model.dividerHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var rightAffordance: some View {
        if model.requiresSettings {
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
        } else {
            OnboardingSwitch(model: model.switchModel)
        }
    }

    private var accessibilityValue: String {
        if model.requiresSettings { return model.valueDenied }
        return model.isGranted ? model.valueGranted : model.valueNotDetermined
    }

    private var accessibilityHint: String {
        // notDetermined (the only "in-app prompt" state) → "Tap to grant".
        // Everything else routes to Settings.
        let willPrompt = !model.requiresSettings && !model.isGranted
        return willPrompt ? model.hintRequestsAccess : model.hintOpensSettings
    }
}

extension OnboardingPermissionRow {
    struct Model {
        let icon: String
        let title: String
        let body: String
        /// Drives the switch's on/off visual (when shown). True iff the
        /// underlying permission is granted in a state our reads can use.
        let isGranted: Bool
        /// When true, the switch is replaced with an inline
        /// `OPEN SETTINGS →` affordance. Means the user can't change
        /// the state in-app and must go to the system Settings app.
        let requiresSettings: Bool
        let switchModel: OnboardingSwitch.Model
        let iconFont: Font
        let iconColor: Color
        let iconMinWidth: CGFloat
        let iconSpacing: CGFloat
        let textSpacing: CGFloat
        let titleFont: Font
        let titleColor: Color
        let bodyFont: Font
        let bodyColor: Color
        let bodyLineSpacing: CGFloat
        let rowVerticalPadding: CGFloat
        let dividerColor: Color
        let dividerHeight: CGFloat
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

extension OnboardingPermissionRow.Model {
    /// Convenience init for EventKit-backed permissions
    /// (calendar / reminders).
    init(
        icon: String,
        title: String,
        body: String,
        status: PermissionAuthStatus,
        action: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.init(
            icon: icon,
            title: title,
            body: body,
            isGranted: status == .fullAccess,
            requiresSettings: status.requiresSettings,
            action: action,
            ds: ds
        )
    }

    /// Convenience init for CoreLocation-backed permission.
    init(
        icon: String,
        title: String,
        body: String,
        status: LocationAuthStatus,
        action: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.init(
            icon: icon,
            title: title,
            body: body,
            isGranted: status.grantsAccess,
            requiresSettings: status.requiresSettings,
            action: action,
            ds: ds
        )
    }

    /// Underlying init shared by both typed convenience inits above.
    /// Direct callers pass the two booleans; specific permission types
    /// translate their enum into the boolean pair.
    init(
        icon: String,
        title: String,
        body: String,
        isGranted: Bool,
        requiresSettings: Bool,
        action: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.icon = icon
        self.title = title
        self.body = body
        self.isGranted = isGranted
        self.requiresSettings = requiresSettings
        self.switchModel = OnboardingSwitch.Model(isOn: isGranted, ds: ds)
        self.iconFont = .system(.title2, design: .default)
        self.iconColor = ds.colors.ink
        self.iconMinWidth = ds.layout.onboardingPermissionRowIconColumn
        self.iconSpacing = ds.spacing.base
        self.textSpacing = ds.spacing.xs
        self.titleFont = .system(.title3, design: .serif)
        self.titleColor = ds.colors.ink
        self.bodyFont = .system(.subheadline, design: .default)
        self.bodyColor = ds.colors.ink2
        self.bodyLineSpacing = ds.spacing.xxs
        self.rowVerticalPadding = ds.spacing.base
        self.dividerColor = ds.colors.rule.opacity(0.6)
        self.dividerHeight = ds.layout.borderWidth

        self.openSettingsLabel = AppStrings.Onboarding.permissionsOpenSettings
        self.openSettingsFont = ds.typography.onboardingTextLink
        self.openSettingsArrowFont = .system(.footnote, design: .serif).weight(.light).italic()
        self.openSettingsArrowSpacing = ds.spacing.xs
        self.openSettingsTracking = ds.typography.monoLinkTracking
        self.openSettingsColor = ds.colors.ink

        self.valueNotDetermined = NSLocalizedString(
            "onboarding.permission.value.not_determined",
            value: "Off",
            comment: "VoiceOver value when a permission row hasn't been asked yet."
        )
        self.valueGranted = NSLocalizedString(
            "onboarding.permission.value.granted",
            value: "On",
            comment: "VoiceOver value when a permission row has been granted."
        )
        self.valueDenied = NSLocalizedString(
            "onboarding.permission.value.denied",
            value: "Off, opens Settings",
            comment: "VoiceOver value when a permission row was denied — tapping opens Settings."
        )
        self.hintRequestsAccess = NSLocalizedString(
            "onboarding.permission.hint.requests",
            value: "Tap to grant access.",
            comment: "VoiceOver hint when the permission row will trigger the system permission prompt."
        )
        self.hintOpensSettings = NSLocalizedString(
            "onboarding.permission.hint.settings",
            value: "Tap to open Settings.",
            comment: "VoiceOver hint when the permission row will route to the Settings app."
        )

        self.action = action
    }
}
