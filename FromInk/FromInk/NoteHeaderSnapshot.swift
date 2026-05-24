import Foundation
import CoreGraphics

/// Value-type projection of `NoteHeader` — a lasso-selected region of ink
/// flagged as a section header. `rect` is in canvas content coordinates,
/// projected from the model's individual `rectX/Y/Width/Height` fields.
struct NoteHeaderSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageID: UUID
    let ocrText: String
    let rect: CGRect
    let createdAt: Date
    let sortOrder: Int
}

// MARK: - Conversion from @Model

extension NoteHeaderSnapshot {
    init(model: NoteHeader) {
        self.id = model.id
        self.pageID = model.page?.id ?? UUID()
        self.ocrText = model.ocrText
        self.rect = model.rect
        self.createdAt = model.createdAt
        self.sortOrder = model.sortOrder
    }
}
