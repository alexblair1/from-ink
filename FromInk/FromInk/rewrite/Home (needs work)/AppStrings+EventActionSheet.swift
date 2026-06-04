import Foundation

extension AppStrings {
    enum EventActionSheet {
        // MARK: - Sheet title

        static let unlinkedTitle = NSLocalizedString(
            "eventActionSheet.unlinked.title",
            value: "Event actions",
            comment: "Branded overlay sheet title shown above the action list for an event that has no linked notebook."
        )

        static let linkedTitle = NSLocalizedString(
            "eventActionSheet.linked.title",
            value: "Linked event",
            comment: "Branded overlay sheet title shown above the action list for an event that already has a linked notebook."
        )

        // MARK: - Action rows (unlinked)

        static let createNotebookFromEvent = NSLocalizedString(
            "eventActionSheet.action.createNotebook",
            value: "Create notebook from event",
            comment: "Action-row label that mints a new notebook prefilled with the event's title and links them."
        )

        static let createNotebookFromReminder = NSLocalizedString(
            "eventActionSheet.action.createNotebookFromReminder",
            value: "Create notebook from reminder",
            comment: "Action-row label that mints a new notebook prefilled with the reminder's title and links them."
        )

        static let linkToExistingNotebook = NSLocalizedString(
            "eventActionSheet.action.linkToExisting",
            value: "Link to existing notebook",
            comment: "Action-row label that opens the notebook picker so the user can attach the calendar item to a notebook they already own."
        )

        // MARK: - Action rows (linked)

        /// "Open notebook \"%@\"" — %@ is the linked notebook's title.
        static func openLinkedNotebook(_ title: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "eventActionSheet.action.openLinkedNotebook",
                    value: "Open notebook \u{201C}%@\u{201D}",
                    comment: "Action-row label that navigates to the notebook this event is linked to. %@ is the notebook title."
                ),
                title
            )
        }

        // MARK: - Action rows (shared)

        static let openInCalendar = NSLocalizedString(
            "eventActionSheet.action.openInCalendar",
            value: "Open in Calendar",
            comment: "Action-row label that hands off to Apple Calendar for the underlying event."
        )

        static let openInReminders = NSLocalizedString(
            "eventActionSheet.action.openInReminders",
            value: "Open in Reminders",
            comment: "Action-row label that hands off to Apple Reminders for the underlying reminder."
        )

        // MARK: - Confirmation copy

        /// Surfaced under the title when the event is part of a
        /// recurring series — sets the user's expectation that a
        /// single notebook will cover every occurrence (per the
        /// project's series-only linking rule).
        static let recurringSeriesCopy = NSLocalizedString(
            "eventActionSheet.recurring.copy",
            value: "This notebook will cover all instances of this meeting.",
            comment: "Subtitle shown when the underlying event has recurrence rules, so the user knows a single notebook covers the whole series."
        )

        // MARK: - Accessibility

        static let dismissAction = NSLocalizedString(
            "eventActionSheet.dismiss",
            value: "Close",
            comment: "VoiceOver label for the X button that closes the event action sheet."
        )

        // MARK: - Row hints (used on the brief row itself)

        static let linkedRowAccessibilityHint = NSLocalizedString(
            "eventActionSheet.row.linkedHint",
            value: "Opens the linked notebook.",
            comment: "VoiceOver hint for a brief event row whose underlying event is already linked to a notebook."
        )

        static let unlinkedRowAccessibilityHint = NSLocalizedString(
            "eventActionSheet.row.unlinkedHint",
            value: "Shows actions for this event.",
            comment: "VoiceOver hint for a brief event row whose underlying event has no linked notebook yet."
        )
    }
}
