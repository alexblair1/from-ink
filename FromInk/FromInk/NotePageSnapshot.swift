import Foundation

/// Lightweight value-type projection of `NotePage` for list views (page
/// navigator, search results). Excludes `drawingData` — opening a page
/// for editing uses `NotePageDetailSnapshot` instead.
///
/// `ocrTextExcerpt` is the first ~200 characters of `NotePage.ocrText`,
/// suitable for displaying a search hit preview without loading the full
/// recognized text.
struct NotePageSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let notebookID: UUID
    let index: Int
    let createdAt: Date
    let modifiedAt: Date
    let templateName: String
    let thumbnailData: Data?
    let ocrTextExcerpt: String?
    let headerCount: Int
    let linkCount: Int
}

// MARK: - Conversion from @Model

extension NotePageSnapshot {
    init(model: NotePage) {
        self.id = model.id
        self.notebookID = model.notebook?.id ?? UUID()
        self.index = model.index
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.templateName = model.templateName
        self.thumbnailData = model.thumbnailData
        self.ocrTextExcerpt = model.ocrText.map { String($0.prefix(200)) }
        self.headerCount = model.headers?.count ?? 0
        self.linkCount = model.links?.count ?? 0
    }
}
