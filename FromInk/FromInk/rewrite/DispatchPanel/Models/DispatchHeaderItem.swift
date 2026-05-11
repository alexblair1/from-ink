import UIKit

/// Value type representing a header captured from the canvas.
/// Converted from CanvasHeader for use in TCA State.
///
struct DispatchHeaderItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let ocrText: String?
    let image: UIImage
    let positionY: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.ocrText == rhs.ocrText
            && lhs.positionY == rhs.positionY
    }
}
