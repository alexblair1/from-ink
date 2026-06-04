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
        /// Sub-minute "now" label used by `relativeTimeLabel` for
        /// recently-modified notebook timestamps (e.g., a notebook
        /// touched <60 seconds ago renders as this instead of "0
        /// seconds ago"). The event-row in-progress state uses an
        /// icon instead of this string.
        static let now = NSLocalizedString(
            "home.now",
            value: "Now",
            comment: "Sub-minute placeholder for notebook 'last touched' timestamps. The event-row in-progress state uses the record-dot icon, not this string."
        )
        /// VoiceOver label for the `record.circle.fill` badge that
        /// marks events currently in progress. The visible indicator
        /// is a SF Symbol; VoiceOver needs an explicit description.
        static let eventInProgressAccessibilityLabel = NSLocalizedString(
            "home.event.inProgress.accessibilityLabel",
            value: "Currently in progress",
            comment: "VoiceOver label for the record-dot icon shown on event rows where startDate <= now < endDate."
        )
        /// VoiceOver label for the checkmark badge that replaces the
        /// trailing time text once an event has passed.
        static let eventPassedAccessibilityLabel = NSLocalizedString(
            "home.event.passed.accessibilityLabel",
            value: "Event ended",
            comment: "VoiceOver label for the checkmark icon shown on event rows whose endDate is in the past."
        )
        static let notebooks = NSLocalizedString(
            "home.notebooks",
            value: "Notebooks",
            comment: "Notebooks shelf section title"
        )

        /// Mono-uppercase affordance shown in the notebooks shelf header
        /// next to the sort label. Tapping opens the full-screen library
        /// browse surface.
        static let viewAll = NSLocalizedString(
            "home.viewAll",
            value: "VIEW ALL ↗",
            comment: "Tappable label in the notebooks shelf that opens the full-screen library browse view."
        )

        static let viewAllAccessibilityLabel = NSLocalizedString(
            "home.viewAll.accessibilityLabel",
            value: "View all library content",
            comment: "VoiceOver label for the View All affordance in the notebooks shelf header."
        )
        static let recentPDFs = NSLocalizedString(
            "home.recentPDFs",
            value: "Recent PDFs",
            comment: "Recent PDFs shelf section title on the home screen"
        )
        static let pdfPagesLabel = NSLocalizedString(
            "home.pdf.pagesLabel",
            value: "PAGES",
            comment: "Mono-label suffix shown next to a PDF page count on the home shelf"
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

        /// Label for the manual brief-refresh action — surfaced as a
        /// VoiceOver custom action and as the haptic-triggered
        /// long-press affordance on the editor's note region.
        static let refreshBrief = NSLocalizedString(
            "home.brief.refresh",
            value: "Refresh brief",
            comment: "VoiceOver custom action name + long-press hint for forcing a daily-brief regeneration."
        )

        /// VoiceOver label for the eye button in the home top bar when
        /// focus mode is OFF (open eye). Tapping enters focus mode, which
        /// hides the editor's note and the calendar/reminders tab strip.
        static let focusModeEnterAccessibilityLabel = NSLocalizedString(
            "home.focus.enter.accessibilityLabel",
            value: "Enter focus mode",
            comment: "VoiceOver label for the open-eye button that collapses the daily brief and tab section on the home screen."
        )

        /// VoiceOver label for the eye button in the home top bar when
        /// focus mode is ON (eye with slash). Tapping exits focus mode
        /// and restores the editor's note + tab strip.
        static let focusModeExitAccessibilityLabel = NSLocalizedString(
            "home.focus.exit.accessibilityLabel",
            value: "Exit focus mode",
            comment: "VoiceOver label for the slashed-eye button that restores the daily brief and tab section on the home screen."
        )
    }
}
