import Foundation

/// Value type representing a link captured from the canvas.
/// Adapted from `NoteLinkSnapshot` (external-destination only) for use
/// in TCA State on the dispatch panel.
///
struct DispatchLinkItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let recognizedText: String
    let url: URL
}
