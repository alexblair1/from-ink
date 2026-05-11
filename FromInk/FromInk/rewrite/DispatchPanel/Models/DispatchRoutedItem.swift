import Foundation

/// Value type representing a routed item (calendar event, reminder, etc.).
/// Converted from RoutedItem SwiftData model for use in TCA State.
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
