import Foundation

/// Value-type projection of `NoteHistoryEntry` — a unified timeline of
/// events, reminders, and routed-task records anchored to a page.
///
/// The `kind` discriminates which payload fields are meaningful. Reading
/// reminder fields on an `event` entry returns the model's zero defaults
/// (empty strings, nil dates) — that's the EDD's intentional flat-fields
/// design so CloudKit can index every scalar without per-kind tables.
struct NoteHistoryEntrySnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageID: UUID
    let timestamp: Date
    let kind: HistoryKind

    // Event context (meaningful when kind == .event)
    let eventTitle: String
    let eventStartDate: Date?
    let eventEndDate: Date?
    let eventCalendarName: String

    // Reminder context (meaningful when kind == .reminder)
    let reminderTitle: String
    let reminderDueDate: Date?

    // Task context (meaningful when kind.rawValue.hasPrefix("task_"))
    let taskTitle: String
    let taskDestination: String          // Integration.rawValue
    let taskDestinationURL: String
    let taskEventKitIdentifier: String?
    let taskStatus: String               // "sent" | "deleted" | "completed"
}

// MARK: - Conversion from @Model

extension NoteHistoryEntrySnapshot {
    init(model: NoteHistoryEntry) {
        self.id = model.id
        self.pageID = model.page?.id ?? UUID()
        self.timestamp = model.timestamp
        self.kind = HistoryKind(rawValue: model.kind) ?? .event
        self.eventTitle = model.eventTitle
        self.eventStartDate = model.eventStartDate
        self.eventEndDate = model.eventEndDate
        self.eventCalendarName = model.eventCalendarName
        self.reminderTitle = model.reminderTitle
        self.reminderDueDate = model.reminderDueDate
        self.taskTitle = model.taskTitle
        self.taskDestination = model.taskDestination
        self.taskDestinationURL = model.taskDestinationURL
        self.taskEventKitIdentifier = model.taskEventKitIdentifier
        self.taskStatus = model.taskStatus
    }
}
