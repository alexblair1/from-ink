import Foundation

extension AppStrings {
    enum Home {
        static let title = NSLocalizedString(
            "home.title",
            value: "From Ink",
            comment: "Home screen wordmark"
        )
static let highlights = NSLocalizedString(
            "home.highlights",
            value: "Highlights",
            comment: "Brief highlights section label"
        )
        static let collapse = NSLocalizedString(
            "home.collapse",
            value: "Collapse",
            comment: "Collapse expanded brief"
        )
        static let readMore = NSLocalizedString(
            "home.readMore",
            value: "Read More",
            comment: "Expand brief"
        )
        static let viewDetails = NSLocalizedString(
            "home.viewDetails",
            value: "View details",
            comment: "View full brief details"
        )
        static let startWriting = NSLocalizedString(
            "home.startWriting",
            value: "Start writing",
            comment: "Empty state title"
        )
        static let emptySubtitle = NSLocalizedString(
            "home.emptySubtitle",
            value: "Create your first notebook to begin.",
            comment: "Empty state subtitle"
        )
        static let newNotebook = NSLocalizedString(
            "home.newNotebook",
            value: "New Notebook",
            comment: "New notebook button/dialog title"
        )
        static let createAndOpen = NSLocalizedString(
            "home.createAndOpen",
            value: "Create & Open",
            comment: "Create and open new notebook"
        )
        static let searchPlaceholder = NSLocalizedString(
            "home.searchPlaceholder",
            value: "Search folders, notebooks and pages",
            comment: "Home search placeholder"
        )
        static let dailyBrief = NSLocalizedString(
            "home.dailyBrief",
            value: "Daily brief",
            comment: "Daily brief section label"
        )
        static let lastModified = NSLocalizedString(
            "home.lastModified",
            value: "Last modified",
            comment: "Notebooks sort label"
        )
        static let nextUp = NSLocalizedString(
            "home.nextUp",
            value: "Next up",
            comment: "Next event highlight label"
        )
        static let upcoming = NSLocalizedString(
            "home.upcoming",
            value: "Upcoming",
            comment: "Upcoming event highlight label"
        )
        static let overdue = NSLocalizedString(
            "home.overdue",
            value: "Overdue",
            comment: "Overdue reminder label"
        )
        static let today = NSLocalizedString(
            "home.today",
            value: "Today",
            comment: "Today reminder label"
        )
        static let birthday = NSLocalizedString(
            "home.birthday",
            value: "Birthday",
            comment: "Birthday highlight label"
        )
        static let titleLabel = NSLocalizedString(
            "home.titleLabel",
            value: "Title",
            comment: "Title field label"
        )
        static let events = NSLocalizedString(
            "home.events",
            value: "events",
            comment: "Events count label"
        )
        static let due = NSLocalizedString(
            "home.due",
            value: "due",
            comment: "Due reminders count label"
        )
        static let onTheShelf = NSLocalizedString(
            "home.onTheShelf",
            value: "on the shelf",
            comment: "Notebook count suffix"
        )
        static let synced = NSLocalizedString(
            "home.synced",
            value: "Synced",
            comment: "Sync status prefix"
        )
        static let justNow = NSLocalizedString(
            "home.justNow",
            value: "just now",
            comment: "Sync status just now"
        )
        static let allDay = NSLocalizedString(
            "home.allDay",
            value: "All day",
            comment: "All-day event badge"
        )
        static let anytime = NSLocalizedString(
            "home.anytime",
            value: "Anytime",
            comment: "Badge / category for reminders with no specific time"
        )
        static let now = NSLocalizedString(
            "home.now",
            value: "Now",
            comment: "Current event or recent time badge"
        )
        static let notebooks = NSLocalizedString(
            "home.notebooks",
            value: "Notebooks",
            comment: "Notebooks shelf section title"
        )
        static let noEventsToday = NSLocalizedString(
            "home.noEventsToday",
            value: "No events or reminders today. A clear day for deep work.",
            comment: "Empty brief fallback text"
        )
        static let tabCalendar = NSLocalizedString(
            "home.tab.calendar",
            value: "Calendar",
            comment: "Brief header tab — calendar events for the selected day."
        )
        static let tabReminders = NSLocalizedString(
            "home.tab.reminders",
            value: "Reminders",
            comment: "Brief header tab — reminders due on the selected day."
        )
        static let tabBirthdays = NSLocalizedString(
            "home.tab.birthdays",
            value: "Birthdays",
            comment: "Brief header tab — birthdays on the selected day."
        )
        static let emptyCalendar = NSLocalizedString(
            "home.empty.calendar",
            value: "No events scheduled.",
            comment: "Empty-state message in the Calendar tab when no events are on the selected day."
        )
        static let emptyReminders = NSLocalizedString(
            "home.empty.reminders",
            value: "Nothing due today.",
            comment: "Empty-state message in the Reminders tab when no reminders are on the selected day."
        )
        static let emptyBirthdays = NSLocalizedString(
            "home.empty.birthdays",
            value: "No birthdays today.",
            comment: "Empty-state message in the Birthdays tab when no birthdays are on the selected day."
        )

        /// "4 events" / "1 event" — pluralized via Foundation's plural rules
        /// when the `.stringsdict` ships. For now uses a single localized
        /// format string and lets the translator handle pluralization.
        static func eventCountSummary(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "home.count.events",
                    value: "%d events",
                    comment: "Count summary for the Calendar tab body. %d is the number of events."
                ),
                count
            )
        }

        static func reminderCountSummary(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "home.count.reminders",
                    value: "%d due",
                    comment: "Count summary for the Reminders tab body. %d is the number due."
                ),
                count
            )
        }

        static func birthdayCountSummary(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "home.count.birthdays",
                    value: "%d birthdays",
                    comment: "Count summary for the Birthdays tab body. %d is the number of birthdays."
                ),
                count
            )
        }

        static let noEventsScheduled = NSLocalizedString(
            "home.noEventsScheduled",
            value: "No events scheduled today.",
            comment: "Empty calendar fallback text"
        )
/// Shown when the user has warped to a past or future day with no
        /// recorded brief. The `%@` placeholder takes a locale-formatted
        /// long date — e.g. "No brief for Tuesday, May 7, 2026."
        static func noBriefForDate(_ formattedDate: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "home.noBriefForDate",
                    value: "No brief for %@.",
                    comment: "Empty brief message shown when the user has warped to a day with no recorded brief. Placeholder is the localized long-form date."
                ),
                formattedDate
            )
        }

        /// VoiceOver hint for the masthead button when the wheel is closed.
        static let mastheadOpenHint = NSLocalizedString(
            "home.masthead.open.hint",
            value: "Double tap to open the date scrub wheel.",
            comment: "VoiceOver hint for the masthead date when the Time Warp wheel is closed."
        )

        /// VoiceOver hint for the masthead button when the wheel is open.
        static let mastheadCloseHint = NSLocalizedString(
            "home.masthead.close.hint",
            value: "Double tap to close the date scrub wheel.",
            comment: "VoiceOver hint for the masthead date when the Time Warp wheel is open."
        )

        /// "Synced %@" where %@ is a locale-formatted relative time like
        /// "just now" or "5 minutes ago". Translators may reorder.
        static func syncedRelative(_ relative: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "home.syncedRelative",
                    value: "Synced %@",
                    comment: "Sync status. %@ is a locale-formatted relative time produced by RelativeDateTimeFormatter (e.g. 'just now', '5 minutes ago')."
                ),
                relative
            )
        }

        // Daily-brief fallback prose has been removed (Daily Brief
        // hides its editor's note section when FM cannot generate
        // one). See `localization_edd.md §5` for the rationale and
        // the "hide-rather-than-fake" principle.
    }
}
