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

    /// Type-anchored view of `destination` — `String` is the persisted
    /// form (schema flexibility), but `DispatchFeature.State.Destination`
    /// is the canonical enum. Returns nil for unknown strings (a row
    /// persisted by a future destination this build doesn't recognize).
    ///
    /// Use this at call sites rather than comparing `destination ==
    /// "calendar"` directly so the bridge between the persisted string
    /// and the enum lives in one place — renaming a destination's raw
    /// value won't silently break observers.
    var destinationKind: DispatchFeature.State.Destination? {
        DispatchFeature.State.Destination(rawValue: destination)
    }
}
