import Foundation

extension AppStrings {
    enum Home {
        static let title = NSLocalizedString(
            "home.title",
            value: "From Ink",
            comment: "Home screen wordmark"
        )
        static let editorsNote = NSLocalizedString(
            "home.editorsNote",
            value: "Editor's note",
            comment: "AI editorial section label"
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
        static let noEventsScheduled = NSLocalizedString(
            "home.noEventsScheduled",
            value: "No events scheduled today.",
            comment: "Empty calendar fallback text"
        )
        static let scrubDates = NSLocalizedString(
            "home.scrubDates",
            value: "Scrub dates",
            comment: "Time Warp wheel disclosure label, shown beside the masthead date."
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
    }
}
