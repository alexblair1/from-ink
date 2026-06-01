import Foundation

/// Value-type projection of `ImportedPDF` for list views (home library
/// PDFs section, search results). Excludes the heavy `sourcePDFData`
/// blob — open the PDF for viewing via a future `PDFFeature` that
/// fetches bytes through a dedicated client call on demand.
struct ImportedPDFSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let modifiedAt: Date
    let lastOpenedAt: Date?
    let contentHash: String
    let byteSize: Int
    let pageCount: Int
    let folderID: UUID?
    let thumbnailData: Data?
}

// MARK: - Conversion from @Model

extension ImportedPDFSnapshot {
    init(model: ImportedPDF) {
        self.id = model.id
        self.title = model.title
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.lastOpenedAt = model.lastOpenedAt
        self.contentHash = model.contentHash
        self.byteSize = model.byteSize
        self.pageCount = model.pageCount
        self.folderID = model.folder?.id
        self.thumbnailData = model.thumbnailData
    }
}
