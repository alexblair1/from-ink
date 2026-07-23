import Foundation

/// Lightweight value-type projection of `NotePage` for list views (page
/// navigator, search results). Excludes block payloads — opening a page
/// for editing loads blocks via `fetchBlocksForPage`.
///
/// `ocrTextExcerpt` is the first ~200 characters of the page's
/// block-aware `extractedText` aggregate (text plainText ∪ ink OCR ∪
/// voice transcripts, in block order) — a search-hit preview without
/// loading full payloads. The name predates the block model; it now
/// covers more than OCR.
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

    /// Typed projection of `templateName`. Unrecognized strings
    /// (e.g. legacy "blank" rows persisted before the schema lined up
    /// with `CanvasTemplate.none.rawValue`) decode as `.none` so the
    /// canvas always has something safe to render.
    var template: CanvasTemplate {
        CanvasTemplate(rawValue: templateName) ?? .none
    }
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
        self.ocrTextExcerpt = model.extractedText.map { String($0.prefix(200)) }
        self.headerCount = model.headers?.count ?? 0
        self.linkCount = model.links?.count ?? 0
    }
}
