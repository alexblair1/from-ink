import UIKit

/// Value type representing a header captured from the canvas. Sourced
/// from `NoteHeaderSnapshot` plus a transient lasso preview image (held
/// only in memory — `NoteHeaderSnapshot` does not persist images).
struct DispatchHeaderItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let ocrText: String?
    let image: UIImage?
    let positionY: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.ocrText == rhs.ocrText
            && lhs.positionY == rhs.positionY
    }
}
