import Foundation

/// Strings for the unified Dispatch modal. Separate namespace from
/// `AppStrings.Dispatch` (which holds strings for the older
/// DispatchPanel side feature) to keep the new modal isolated.
extension AppStrings {
    enum DispatchModal {
        static let titleDispatch = NSLocalizedString(
            "dispatch.modal.title.dispatch",
            value: "Dispatch",
            comment: "Modal eyebrow when sending one captured line"
        )
        static let titleTasks = NSLocalizedString(
            "dispatch.modal.title.tasks",
            value: "Tasks",
            comment: "Modal eyebrow when cycling through page-OCR tasks"
        )

        static let line = NSLocalizedString(
            "dispatch.modal.line",
            value: "LINE",
            comment: "Section label for the captured line"
        )
        static let extracting = NSLocalizedString(
            "dispatch.modal.extracting",
            value: "Reading your notes…",
            comment: "Placeholder shown in the line section while OCR / extraction is running"
        )
        static let locationSearchFailed = NSLocalizedString(
            "dispatch.modal.location.searchFailed",
            value: "We couldn't resolve that place. Try another search.",
            comment: "Error message when MKLocalSearch returns no map items for a tapped suggestion"
        )
        static let edit = NSLocalizedString(
            "dispatch.modal.edit",
            value: "Edit",
            comment: "Button to enter line edit mode"
        )
        static let done = NSLocalizedString(
            "dispatch.modal.done",
            value: "Done",
            comment: "Button to exit line edit mode"
        )

        static let sendTo = NSLocalizedString(
            "dispatch.modal.sendTo",
            value: "Send to",
            comment: "Section label above the destination grid"
        )

        static let calendar = NSLocalizedString(
            "dispatch.modal.dest.calendar",
            value: "Calendar",
            comment: "Destination chip label"
        )
        static let reminders = NSLocalizedString(
            "dispatch.modal.dest.reminders",
            value: "Reminders",
            comment: "Destination chip label"
        )
        static let mail = NSLocalizedString(
            "dispatch.modal.dest.mail",
            value: "Mail",
            comment: "Destination chip label"
        )

        // Field labels per destination
        static let date = NSLocalizedString(
            "dispatch.modal.field.date",
            value: "Date",
            comment: "Calendar field label — start date (separate from time)"
        )
        static let time = NSLocalizedString(
            "dispatch.modal.field.time",
            value: "Time",
            comment: "Calendar field label — start time (separate from date)"
        )
        static let endDate = NSLocalizedString(
            "dispatch.modal.field.endDate",
            value: "End Date",
            comment: "Calendar field label — end date (separate from end time)"
        )
        static let endTime = NSLocalizedString(
            "dispatch.modal.field.endTime",
            value: "End Time",
            comment: "Calendar field label — end time (separate from end date)"
        )
        static let url = NSLocalizedString(
            "dispatch.modal.field.url",
            value: "URL",
            comment: "Calendar field label — URL attached to the event (zoom link, doc link, etc.)"
        )
        static let urlPlaceholder = NSLocalizedString(
            "dispatch.modal.field.url.placeholder",
            value: "https://",
            comment: "Placeholder text inside the URL inline text field on the Calendar dispatch form"
        )
        static let location = NSLocalizedString(
            "dispatch.modal.field.location",
            value: "Location",
            comment: "Calendar field label — event location (free text or MapKit autocomplete pick)"
        )
        static let locationPlaceholder = NSLocalizedString(
            "dispatch.modal.field.location.placeholder",
            value: "Search or type a place",
            comment: "Placeholder inside the Location field when empty"
        )
        /// `repeat` is a Swift reserved word, so the property is named
        /// `repeatLabel`. The localized key stays `dispatch.modal.field.repeat`.
        static let repeatLabel = NSLocalizedString(
            "dispatch.modal.field.repeat",
            value: "Repeat",
            comment: "Calendar field label — event recurrence (Never, Daily, Weekly, etc.)"
        )
        static let repeatNever = NSLocalizedString(
            "dispatch.modal.repeat.never",
            value: "Never",
            comment: "Recurrence picker option — no repeat (single-shot event)"
        )
        static let repeatDaily = NSLocalizedString(
            "dispatch.modal.repeat.daily",
            value: "Every Day",
            comment: "Recurrence picker option — repeat daily"
        )
        static let repeatWeekly = NSLocalizedString(
            "dispatch.modal.repeat.weekly",
            value: "Every Week",
            comment: "Recurrence picker option — repeat weekly"
        )
        static let repeatBiweekly = NSLocalizedString(
            "dispatch.modal.repeat.biweekly",
            value: "Every 2 Weeks",
            comment: "Recurrence picker option — repeat every two weeks"
        )
        static let repeatMonthly = NSLocalizedString(
            "dispatch.modal.repeat.monthly",
            value: "Every Month",
            comment: "Recurrence picker option — repeat monthly"
        )
        static let repeatYearly = NSLocalizedString(
            "dispatch.modal.repeat.yearly",
            value: "Every Year",
            comment: "Recurrence picker option — repeat yearly"
        )
        static let alertLabel = NSLocalizedString(
            "dispatch.modal.field.alert",
            value: "Alert",
            comment: "Calendar field label — single-alarm offset before the event starts"
        )
        static let alertNone = NSLocalizedString(
            "dispatch.modal.alert.none",
            value: "None",
            comment: "Alert picker option — no alarm"
        )
        static let alertAtTime = NSLocalizedString(
            "dispatch.modal.alert.atTime",
            value: "At time of event",
            comment: "Alert picker option — alarm fires at the start of the event"
        )
        static let alertFiveMin = NSLocalizedString(
            "dispatch.modal.alert.fiveMin",
            value: "5 minutes before",
            comment: "Alert picker option — alarm 5 minutes before event start"
        )
        static let alertFifteenMin = NSLocalizedString(
            "dispatch.modal.alert.fifteenMin",
            value: "15 minutes before",
            comment: "Alert picker option — alarm 15 minutes before event start"
        )
        static let alertThirtyMin = NSLocalizedString(
            "dispatch.modal.alert.thirtyMin",
            value: "30 minutes before",
            comment: "Alert picker option — alarm 30 minutes before event start"
        )
        static let alertOneHour = NSLocalizedString(
            "dispatch.modal.alert.oneHour",
            value: "1 hour before",
            comment: "Alert picker option — alarm 1 hour before event start"
        )
        static let alertOneDay = NSLocalizedString(
            "dispatch.modal.alert.oneDay",
            value: "1 day before",
            comment: "Alert picker option — alarm 1 day before event start"
        )
        /// Format string for non-preset alarm offsets loaded from an
        /// existing EKEvent (e.g. a 7-minute alarm set outside our
        /// quick-pick list). The terse "min" abbreviation sidesteps
        /// the English singular/plural issue ("1 minute" vs "5
        /// minutes") that a `.stringsdict` would otherwise be needed
        /// to handle. Translators still rearrange word order
        /// naturally within the format string at translation time.
        static let alertCustomMinutes = NSLocalizedString(
            "dispatch.modal.alert.customMinutes",
            value: "%d min before",
            comment: "Alert picker option for a non-preset minutes-before-event value loaded from an existing event. %d is replaced with the minutes count."
        )
        static let editLoadEventNotFound = NSLocalizedString(
            "dispatch.modal.edit.loadFailed.notFound",
            value: "Event not found.",
            comment: "Error message shown when opening an existing event for editing but it can no longer be fetched from the calendar database (e.g. deleted out of band)."
        )
        static let when = NSLocalizedString(
            "dispatch.modal.field.when",
            value: "When",
            comment: "Calendar field label — start moment"
        )
        static let duration = NSLocalizedString(
            "dispatch.modal.field.duration",
            value: "Duration",
            comment: "Calendar field label — duration"
        )
        static let list = NSLocalizedString(
            "dispatch.modal.field.list",
            value: "List",
            comment: "Reminders field label — target list"
        )
        static let due = NSLocalizedString(
            "dispatch.modal.field.due",
            value: "Due",
            comment: "Reminders field label — due date"
        )
        static let to = NSLocalizedString(
            "dispatch.modal.field.to",
            value: "To",
            comment: "Mail field label — recipient"
        )
        static let subject = NSLocalizedString(
            "dispatch.modal.field.subject",
            value: "Subject",
            comment: "Mail field label — subject"
        )
        static let mailToPlaceholder = NSLocalizedString(
            "dispatch.modal.mail.toPlaceholder",
            value: "name@example.com",
            comment: "Placeholder for the Mail recipient field"
        )
        static let mailSubjectPlaceholder = NSLocalizedString(
            "dispatch.modal.mail.subjectPlaceholder",
            value: "Subject",
            comment: "Placeholder for the Mail subject field"
        )

        static let noteLabel = NSLocalizedString(
            "dispatch.modal.note.label",
            value: "Add a note · optional",
            comment: "Optional note section label"
        )
        static let notePlaceholder = NSLocalizedString(
            "dispatch.modal.note.placeholder",
            value: "A line of context for the receiver…",
            comment: "Placeholder for the optional context note"
        )

        // Footer actions
        static let cancel = NSLocalizedString(
            "dispatch.modal.cancel",
            value: "Cancel",
            comment: "Footer cancel button"
        )
        static let skip = NSLocalizedString(
            "dispatch.modal.skip",
            value: "Skip",
            comment: "Footer skip button (stack mode only)"
        )
        static let sending = NSLocalizedString(
            "dispatch.modal.sending",
            value: "Sending…",
            comment: "Footer primary button label while in flight"
        )
        static let sentLabel = NSLocalizedString(
            "dispatch.modal.sent",
            value: "Sent",
            comment: "Footer primary button label after success"
        )

        // Permission card
        static let accessNeededTemplate = NSLocalizedString(
            "dispatch.modal.perm.needed",
            value: "%@ access needed",
            comment: "Permission card eyebrow when destination not granted yet. %@ is the destination label."
        )
        static let accessDeniedTemplate = NSLocalizedString(
            "dispatch.modal.perm.denied",
            value: "%@ access is off",
            comment: "Permission card eyebrow when destination access is denied. %@ is the destination label."
        )
        static let permCalendarVerb = NSLocalizedString(
            "dispatch.modal.perm.verb.calendar",
            value: "create events and time-blocks",
            comment: "Verb phrase in the Calendar permission card body"
        )
        static let permRemindersVerb = NSLocalizedString(
            "dispatch.modal.perm.verb.reminders",
            value: "add tasks to your lists",
            comment: "Verb phrase in the Reminders permission card body"
        )
        static let permGrantedHint = NSLocalizedString(
            "dispatch.modal.perm.hint.granted",
            value: "iOS will ask once. Manageable in Settings later.",
            comment: "Hint shown next to the Allow button"
        )
        static let permDeniedHintTemplate = NSLocalizedString(
            "dispatch.modal.perm.hint.denied",
            value: "Settings · Privacy · %@",
            comment: "Hint shown next to Open Settings when access is denied. %@ is the destination label."
        )
        static let permAllowTemplate = NSLocalizedString(
            "dispatch.modal.perm.allow",
            value: "Allow %@",
            comment: "Allow button label — %@ is the destination label."
        )
        static let permOpenSettings = NSLocalizedString(
            "dispatch.modal.perm.openSettings",
            value: "Open Settings",
            comment: "Button label that opens system Settings to the relevant privacy pane"
        )

        static func sendToButton(destination: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "dispatch.modal.send.template",
                    value: "Send to %@",
                    comment: "Primary send button label. %@ is the destination label."
                ),
                destination
            )
        }
    }
}
