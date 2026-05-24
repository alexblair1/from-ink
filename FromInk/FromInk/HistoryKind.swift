import Foundation

/// Discriminator for `NoteHistoryEntry`. Stored on `NoteHistoryEntry.kind`
/// as a raw `String` (CloudKit cannot encode enums natively) and exposed
/// via the computed `NoteHistoryEntry.historyKind` bridge.
///
/// The raw values use snake_case so CloudKit indexes group naturally for
/// future cross-cutting queries ("all task_routed entries this week").
enum HistoryKind: String, Codable, CaseIterable, Sendable {
    /// EventKit calendar event surfaced into the page's history.
    case event
    /// EventKit reminder surfaced into the page's history.
    case reminder
    /// Task extracted from ink + routed to an integration (Linear, Slack, etc.).
    case taskRouted = "task_routed"
    /// Routed task confirmed completed in the destination system.
    case taskCompleted = "task_completed"
    /// Routed task confirmed deleted from the destination system.
    case taskDeleted = "task_deleted"
}
