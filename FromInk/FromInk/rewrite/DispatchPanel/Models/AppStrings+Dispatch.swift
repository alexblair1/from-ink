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
