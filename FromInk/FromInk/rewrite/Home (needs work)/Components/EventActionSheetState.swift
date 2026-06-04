import Foundation

/// Pure-data presentation surface for the event action sheet. Stored on
/// `HomeFeature.State` via `@Presents` and consumed by
/// `EventActionSheetView` through its Model. No reducer of its own —
/// the action sheet is a presentation shell on top of input data; every
/// user tap routes back through `HomeFeature` actions.
///
/// **Linked vs. unlinked branches:**
/// - `linkedNotebook == nil` (unlinked): the sheet offers Create / Link /
///   Open in Calendar.
/// - `linkedNotebook != nil` (linked): the sheet offers Open notebook /
///   Open in Calendar. The Create + Link actions are suppressed entirely
///   per the strict 1:1 rule (`CalendarItemLink` enforces uniqueness at
///   the service layer; the UI hides the option that would violate it).
///
struct EventActionSheetState: Equatable {
    /// EventKit `eventIdentifier` or `calendarItemIdentifier`. Used to
    /// resolve the link service on Create / Link confirmations.
    let identifier: String

    /// External (iCloud / CalDAV) identifier so a freshly created link
    /// can survive the user moving the event between calendars later.
    let externalIdentifier: String?

    /// `.event` for now — `.reminder` lands in PR4 (reminders parity).
    let kind: CalendarItemKind

    /// Event title — used as the default notebook title on Create.
    let eventTitle: String

    /// True when the underlying event has recurrence rules. Surfaces
    /// the "this notebook will cover all instances" copy so the user
    /// understands the scope before confirming.
    let hasRecurrenceRules: Bool

    /// Non-nil when an existing link is associated with `identifier`.
    /// Drives the linked branch of the action list.
    let linkedNotebook: LinkedNotebook?

    struct LinkedNotebook: Equatable {
        let notebookID: UUID
        let notebookTitle: String
        let pageID: UUID?
    }
}
