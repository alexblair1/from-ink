import Foundation
import SwiftData

/// Unified history timeline anchored to a `NotePage`. Event/reminder rows
/// come from EventKit observation; task rows come from the dispatch
/// pipeline routing extracted tasks to external integrations.
///
/// **Flat-fields design (per `data_model_edd.md` §4.8):** rather than
/// one table per kind or one JSON blob, every contextual field lives at
/// the top level. CloudKit indexes scalars natively, enabling future
/// cross-cutting queries like "all task_routed entries this week" without
/// per-kind table joins. The `kind` discriminator tells callers which
/// fields are meaningful; non-applicable fields hold their zero defaults.
///
/// Replaces the earlier `RoutedItem` model (which only tracked task
/// dispatches). Migration happens in Step 6.
@Model final class NoteHistoryEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var kind: String = HistoryKind.event.rawValue

    // Event context (kind == .event)
    var eventTitle: String = ""
    var eventStartDate: Date?
    var eventEndDate: Date?
    var eventCalendarName: String = ""

    // Reminder context (kind == .reminder)
    var reminderTitle: String = ""
    var reminderDueDate: Date?

    // Task context (kind.hasPrefix("task_"))
    var taskTitle: String = ""
    var taskDestination: String = ""        // Integration.rawValue
    var taskDestinationURL: String = ""
    var taskEventKitIdentifier: String?
    var taskStatus: String = "sent"         // "sent" | "deleted" | "completed"

    var page: NotePage?

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        kind: HistoryKind,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.page = page
        self.kind = kind.rawValue
        self.timestamp = timestamp
    }

    var historyKind: HistoryKind {
        get { HistoryKind(rawValue: kind) ?? .event }
        set { kind = newValue.rawValue }
    }
}
