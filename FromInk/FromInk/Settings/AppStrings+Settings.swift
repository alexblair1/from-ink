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
        static let integrationsScreenTitle = NSLocalizedString("settings.integrations.title", value: "Integrations.", comment: "Integrations screen title — serif with trailing period per the editorial design system")

        // Per-provider group headers — `Adding` is appended dynamically
        // when a pending add-account flow is in-flight for that provider.
        static let integrationsProviderLinear = NSLocalizedString("settings.integrations.provider.linear", value: "Linear", comment: "Linear provider group header in the Integrations screen")
        static let integrationsProviderSlack = NSLocalizedString("settings.integrations.provider.slack", value: "Slack", comment: "Slack provider group header in the Integrations screen")
        static let integrationsAddingSuffix = NSLocalizedString("settings.integrations.adding.suffix", value: " · Adding", comment: "Suffix appended to the provider group header while an add-account flow is in-flight (e.g., `Linear · Adding`). Includes leading space + middle dot.")

        // Per-screen count chip — "<connected>/<total>". Format is locale-aware via String.localizedStringWithFormat.
        static func integrationsCountChip(_ connected: Int, of total: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "settings.integrations.count",
                    value: "%1$d of %2$d",
                    comment: "Connected providers count, e.g. '2 of 4'. %1$d is the count of providers with at least one account; %2$d is the total supported providers."
                ),
                connected, total
            )
        }

        // Action row at the bottom of each provider group.
        static let integrationsAddAccount = NSLocalizedString("settings.integrations.addAccount", value: "+ Add account", comment: "Action row label that initiates the add-account flow for the surrounding provider group")

        // Pending-row labels — italic serif name shown while the
        // add-account flow runs and the account itself isn't known yet.
        static let integrationsPendingConnecting = NSLocalizedString("settings.integrations.pending.connecting", value: "Connecting…", comment: "Pending-row title while the add-account flow is connecting to the provider")
        static let integrationsStatusPKCE = NSLocalizedString("settings.integrations.status.pkce", value: "PKCE", comment: "Mono uppercase status tag shown on the pending row while PKCE handshake is in flight")
        static let integrationsStatusVerifying = NSLocalizedString("settings.integrations.status.verifying", value: "Verifying", comment: "Mono uppercase status tag shown while exchanging the auth code for a token")
        static let integrationsStatusCancelled = NSLocalizedString("settings.integrations.status.cancelled", value: "Cancelled", comment: "Neutral mono uppercase status tag shown when the user cancelled the auth sheet")
        static let integrationsStatusPermissionsDenied = NSLocalizedString("settings.integrations.status.permissionsDenied", value: "Permissions denied", comment: "Flag-red mono uppercase status tag shown when the vendor returned access_denied")
        static let integrationsStatusNoConnection = NSLocalizedString("settings.integrations.status.noConnection", value: "No connection", comment: "Flag-red mono uppercase status tag shown when the network or vendor failed")
        static let integrationsStatusCouldntVerify = NSLocalizedString("settings.integrations.status.couldntVerify", value: "Couldn't verify", comment: "Flag-red mono uppercase status tag shown when the PKCE state nonce didn't match (CSRF guard tripped)")

        // Existing-account row label when token refresh fails / expires.
        static let integrationsReauthenticate = NSLocalizedString("settings.integrations.reauthenticate", value: "Re-authenticate", comment: "Flag-red mono uppercase label shown on an existing-account row when its token has expired and cannot be refreshed")

        // "Make default?" prompt card.
        static let integrationsDefaultCaption = NSLocalizedString("settings.integrations.default.caption", value: "Just added", comment: "Mono uppercase caption above the make-default question card")

        static func integrationsDefaultQuestion(_ name: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "settings.integrations.default.question",
                    value: "Make %@ your default?",
                    comment: "Question on the make-default prompt card. %@ is the new account's display name."
                ),
                name
            )
        }

        static func integrationsDefaultKeep(_ currentName: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "settings.integrations.default.keep",
                    value: "No, keep %@",
                    comment: "Button label that keeps the current default account. %@ is the current default account's name."
                ),
                currentName
            )
        }

        static let integrationsDefaultSwitch = NSLocalizedString("settings.integrations.default.switch", value: "Yes, switch", comment: "Button label that switches the default to the newly-added account")

        // Empty-state copy — kept from prior stub so the file builds when
        // a provider has zero accounts and zero pending adds. Used by the
        // empty-section message inside a provider group.
        static let integrationsEmptyTitle = NSLocalizedString("settings.integrations.empty.title", value: "No accounts connected", comment: "Empty-state title shown inside a provider group with zero accounts and no pending add")
        static let integrationsEmptyBody = NSLocalizedString("settings.integrations.empty.body", value: "Tap + Add account to connect.", comment: "Empty-state body shown inside a provider group with zero accounts and no pending add")

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
