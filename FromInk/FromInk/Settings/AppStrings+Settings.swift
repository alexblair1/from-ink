import Foundation

extension AppStrings {
    enum Settings {
        static let title = NSLocalizedString("settings.title", value: "Settings.", comment: "Settings sheet title — serif with trailing period per the editorial design system")

        // MARK: - Group headers (the editorial three-group rhythm)

        static let groupEditor = NSLocalizedString("settings.group.editor", value: "THE EDITOR", comment: "Settings group header — editor-related preferences (appearance, handedness, themes). Mono uppercase per the design system.")
        static let groupYourData = NSLocalizedString("settings.group.yourData", value: "YOUR DATA", comment: "Settings group header — data + access preferences (integrations, permissions). Mono uppercase per the design system.")

        // MARK: - Appearance

        static let appearance = NSLocalizedString("settings.appearance", value: "Appearance", comment: "Appearance row title")
        static let systemAppearance = NSLocalizedString("settings.appearance.system", value: "System", comment: "Follow system appearance")
        static let lightAppearance = NSLocalizedString("settings.appearance.light", value: "Light", comment: "Light mode")
        static let darkAppearance = NSLocalizedString("settings.appearance.dark", value: "Dark", comment: "Dark mode")

        // MARK: - Handedness

        static let handedness = NSLocalizedString("settings.handedness", value: "Handedness", comment: "Handedness row title — controls which side the toolbar lives on")
        static let leftHanded = NSLocalizedString("settings.handedness.left", value: "Left", comment: "Left-handed setting — toolbar on the right so the writing hand has the canvas")
        static let rightHanded = NSLocalizedString("settings.handedness.right", value: "Right", comment: "Right-handed setting — toolbar on the left so the writing hand has the canvas")

        // MARK: - Themes (stub)

        static let themes = NSLocalizedString("settings.themes", value: "Themes", comment: "Themes row title — visual themes beyond light/dark (paper colors, ink tints). Stub until the theme system ships.")
        static let themesEmptyTitle = NSLocalizedString("settings.themes.empty.title", value: "Themes coming soon", comment: "Empty-state title for the Themes screen — feature not yet implemented")
        static let themesEmptyBody = NSLocalizedString("settings.themes.empty.body", value: "Custom paper and ink color palettes will live here in a future update.", comment: "Empty-state body for the Themes screen — explains the section is reserved for the future theme system")

        // MARK: - Integrations

        static let integrations = NSLocalizedString("settings.integrations", value: "Integrations", comment: "Integrations row title — third-party services connected via PKCE")
        static let integrationsEmptyTitle = NSLocalizedString("settings.integrations.empty.title", value: "No integrations yet", comment: "Empty-state title for the Integrations screen")
        static let integrationsEmptyBody = NSLocalizedString("settings.integrations.empty.body", value: "Connect Calendar, Reminders, and third-party services in a future update.", comment: "Empty-state body for the Integrations screen — explains the section is reserved for future PKCE-authenticated integrations")

        // MARK: - Permissions (stub)

        static let permissions = NSLocalizedString("settings.permissions", value: "Permissions", comment: "Permissions row title — system-granted access (Calendar, Reminders, Contacts, Notifications)")
        static let permissionsEmptyTitle = NSLocalizedString("settings.permissions.empty.title", value: "Permissions overview coming soon", comment: "Empty-state title for the Permissions screen — feature not yet implemented")
        static let permissionsEmptyBody = NSLocalizedString("settings.permissions.empty.body", value: "Calendar, Reminders, Contacts, and Notifications access will be reviewable here in a future update.", comment: "Empty-state body for the Permissions screen — explains the section will surface system permission states")
    }
}
