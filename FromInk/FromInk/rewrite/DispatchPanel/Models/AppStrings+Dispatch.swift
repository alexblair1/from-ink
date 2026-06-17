import Foundation

extension AppStrings {
    enum Dispatch {
        static let emptyHeaders = NSLocalizedString(
            "dispatch.empty.headers",
            value: "No headers yet",
            comment: "Empty state for headers tab"
        )
        static let emptyLinks = NSLocalizedString(
            "dispatch.empty.links",
            value: "No links yet",
            comment: "Empty state for links tab"
        )
        static let emptyCalendar = NSLocalizedString(
            "dispatch.empty.calendar",
            value: "No calendar events yet",
            comment: "Empty state for calendar tab"
        )
        static let emptyReminders = NSLocalizedString(
            "dispatch.empty.reminders",
            value: "No reminders yet",
            comment: "Empty state for reminders tab"
        )
        // MARK: Empty-state hints (mono uppercase, shown under the headline)

        static let hintHeaders = NSLocalizedString(
            "dispatch.hint.headers",
            value: "Write a heading on the page to see it here",
            comment: "Empty-state hint for the headers tab"
        )
        static let hintLinks = NSLocalizedString(
            "dispatch.hint.links",
            value: "Add a link or draw one on the page",
            comment: "Empty-state hint for the links tab"
        )
        static let hintCalendar = NSLocalizedString(
            "dispatch.hint.calendar",
            value: "Add an event or route a task here",
            comment: "Empty-state hint for the calendar tab"
        )
        static let hintReminders = NSLocalizedString(
            "dispatch.hint.reminders",
            value: "Add a reminder or route a task here",
            comment: "Empty-state hint for the reminders tab"
        )

        // MARK: Add-action button labels

        static let addLink = NSLocalizedString(
            "dispatch.add.link",
            value: "Add Link",
            comment: "Bottom action button — add a link"
        )
        static let addCalendar = NSLocalizedString(
            "dispatch.add.calendar",
            value: "Add Event",
            comment: "Bottom action button — add a calendar event"
        )
        static let addReminder = NSLocalizedString(
            "dispatch.add.reminder",
            value: "Add Reminder",
            comment: "Bottom action button — add a reminder"
        )

        static let recognizing = NSLocalizedString(
            "dispatch.recognizing",
            value: "Recognizing…",
            comment: "OCR in progress label"
        )
        static let headerPlaceholder = NSLocalizedString(
            "dispatch.header.placeholder",
            value: "—",
            comment: "Placeholder for empty header text"
        )
    }
}
