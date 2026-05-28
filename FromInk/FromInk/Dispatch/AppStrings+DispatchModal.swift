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
