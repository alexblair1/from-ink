import Foundation

/// Value type representing a routed item (calendar event, reminder, etc.).
/// Adapted from `NoteHistoryEntrySnapshot` (kind == .taskRouted) for use
/// in TCA State on the dispatch panel.
///
struct DispatchRoutedItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let destination: String
    let destinationURL: String
    let eventKitIdentifier: String?
    let routedAt: Date
    var isDeleted: Bool
}
