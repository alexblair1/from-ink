import Foundation

extension AppStrings {
    enum Settings {
        static let title = NSLocalizedString("settings.title", value: "Settings.", comment: "Settings sheet title — serif with trailing period per the editorial design system")

        // MARK: - Group headers (the editorial three-group rhythm)

        static let groupEditor = NSLocalizedString("settings.group.editor", value: "THE EDITOR", comment: "Settings group header — editor-related preferences (appearance, handedness, themes). Mono uppercase per the design system.")
        static let groupYourData = NSLocalizedString("settings.group.yourData", value: "YOUR DATA", comment: "Settings group header — system access preferences. Mono uppercase per the design system.")

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

        // MARK: - Permissions (stub)

        static let permissions = NSLocalizedString("settings.permissions", value: "Permissions", comment: "Permissions row title — system-granted access (Calendar, Reminders, Contacts, Notifications)")
        static let permissionsEmptyTitle = NSLocalizedString("settings.permissions.empty.title", value: "Permissions overview coming soon", comment: "Empty-state title for the Permissions screen — feature not yet implemented")
        static let permissionsEmptyBody = NSLocalizedString("settings.permissions.empty.body", value: "Calendar, Reminders, Contacts, and Notifications access will be reviewable here in a future update.", comment: "Empty-state body for the Permissions screen — explains the section will surface system permission states")

        // MARK: - Permission rows

        static let permissionCalendar = NSLocalizedString("settings.permissions.calendar", value: "Calendar", comment: "Permission row title — system Calendar access (EventKit events)")
        static let permissionReminders = NSLocalizedString("settings.permissions.reminders", value: "Reminders", comment: "Permission row title — system Reminders access (EventKit reminders)")

        static let permissionCalendarDescription = NSLocalizedString("settings.permissions.calendar.description", value: "Surfaces today's events in the daily brief and routes dispatched tasks into your calendar.", comment: "Caption below the Calendar permission row explaining what From Ink uses calendar access for")
        static let permissionRemindersDescription = NSLocalizedString("settings.permissions.reminders.description", value: "Surfaces due reminders in the daily brief and routes dispatched tasks into your reminders list.", comment: "Caption below the Reminders permission row explaining what From Ink uses reminder access for")

        // MARK: - Permission status labels (mono uppercase per design system)

        static let permissionStatusNotDetermined = NSLocalizedString("settings.permissions.status.notDetermined", value: "Not yet asked", comment: "Permission status — the user has not yet been prompted")
        static let permissionStatusDenied = NSLocalizedString("settings.permissions.status.denied", value: "Denied", comment: "Permission status — the user explicitly declined")
        static let permissionStatusRestricted = NSLocalizedString("settings.permissions.status.restricted", value: "Restricted", comment: "Permission status — restricted by parental controls / MDM")
        static let permissionStatusWriteOnly = NSLocalizedString("settings.permissions.status.writeOnly", value: "Write only", comment: "Permission status — iOS 17+ write-only EventKit access; we can add events but not read them")
        static let permissionStatusFullAccess = NSLocalizedString("settings.permissions.status.fullAccess", value: "Granted", comment: "Permission status — full read+write access granted")

        // MARK: - Permission row CTAs

        static let permissionCTAGrant = NSLocalizedString("settings.permissions.cta.grant", value: "Tap to grant", comment: "Hint text on a not-yet-asked permission row")
        static let permissionCTAManage = NSLocalizedString("settings.permissions.cta.manage", value: "Manage in Settings", comment: "Hint text on a resolved permission row — tapping opens the system Settings app")
    }
}
