import Foundation

/// Value type representing a link captured from the canvas.
/// Converted from CanvasLink for use in TCA State.
///
struct DispatchLinkItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let recognizedText: String
    let url: URL
}
