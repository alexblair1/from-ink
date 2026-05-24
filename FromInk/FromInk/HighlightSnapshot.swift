import Foundation
import CoreGraphics

/// Value-type projection of `Highlight` — a PDF annotation anchored to
/// a `Notebook` (not a `NotePage`, because PDF page indices don't map to
/// `NotePage` model IDs). `bounds` is normalized 0..1 within the PDF
/// page so it survives re-rendering at any scale.
struct HighlightSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let notebookID: UUID
    let createdAt: Date
    let pageIndex: Int
    let extractedText: String
    let commentary: String
    let bounds: CGRect
}

// MARK: - Conversion from @Model

extension HighlightSnapshot {
    init(model: Highlight) {
        self.id = model.id
        self.notebookID = model.notebook?.id ?? UUID()
        self.createdAt = model.createdAt
        self.pageIndex = model.pageIndex
        self.extractedText = model.extractedText
        self.commentary = model.commentary
        self.bounds = model.bounds
    }
}
