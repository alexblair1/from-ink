import Foundation

/// Lightweight value-type projection of `Notebook` for list views (library grid,
/// folder contents). Excludes per-page payloads — `pageCount` and
/// `firstPageThumbnailData` give cards what they need without loading any
/// `drawingData`.
///
/// For an opened notebook with its full page list, use `NotebookDetailSnapshot`.
struct NotebookSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let modifiedAt: Date
    let coverColorHex: String
    let isPinned: Bool
    let isArchived: Bool
    let sortOrder: Int
    let documentKind: DocumentKind
    let folderID: UUID?
    let pageCount: Int
    let firstPageThumbnailData: Data?
    let tagIDs: [UUID]
}

// MARK: - Conversion from @Model

extension NotebookSnapshot {
    init(model: Notebook) {
        let pages = (model.pages ?? []).sorted { $0.index < $1.index }
        self.id = model.id
        self.title = model.title
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.coverColorHex = model.coverColorHex
        self.isPinned = model.isPinned
        self.isArchived = model.isArchived
        self.sortOrder = model.sortOrder
        self.documentKind = model.documentKind
        self.folderID = model.folder?.id
        self.pageCount = pages.count
        self.firstPageThumbnailData = pages.first?.thumbnailData
        self.tagIDs = (model.tags ?? []).map(\.id)
    }
}
