import Foundation
import SwiftData

/// A single page inside a `Notebook`. Pages are the unit of lazy loading —
/// `drawingData` and `thumbnailData` are marked `@Attribute(.externalStorage)`
/// so SwiftData stores them off-row and CloudKit promotes them to `CKAsset`
/// on sync (avoiding the 1 MB per-record limit).
///
/// **Lifecycle responsibilities owned by `NotebookClient`:**
/// - Reindexing siblings after `transferPage(to:at:)`
/// - Updating `Notebook.modifiedAt` when any page mutates
/// - Cascade deletion of children (`headers` / `links` / `history`) is
///   driven by the `@Relationship(deleteRule: .cascade, inverse: ...)`
///   macros declared on `Notebook.pages` (parent side only). The
///   `notebook` back-pointer below is intentionally plain — declaring
///   `@Relationship` on both sides triggers SwiftData's "duplicate
///   inverse" runtime error.
@Model final class NotePage {
    var id: UUID = UUID()
    var index: Int = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Per-page template selection, stored as `CanvasTemplate.rawValue`.
    /// Default matches `CanvasTemplate.none.rawValue` so a row created
    /// without an explicit template reads as no-template rather than
    /// the legacy "blank" sentinel that the renderer never honored.
    var templateName: String = CanvasTemplate.none.rawValue

    // Ink payload — externalStorage promotes to CKAsset on sync.
    @Attribute(.externalStorage)
    var drawingData: Data?

    @Attribute(.externalStorage)
    var thumbnailData: Data?

    // OCR
    var ocrText: String?
    var ocrUpdatedAt: Date?

    // Typed text (populated when parent Notebook.notebookType == .textNote)
    var typedText: String?

    // ML cache — invalidated when SHA256(ocrText) differs from summaryHash
    var summaryText: String = ""
    var summaryHash: String = ""

    // Parent — Step 3 declares the inverse on Notebook.pages
    var notebook: Notebook?

    // Children — these inverse macros are safe here because the child
    // classes do not declare their own @Relationship on `page`.
    @Relationship(deleteRule: .cascade, inverse: \NoteHeader.page)
    var headers: [NoteHeader]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteLink.page)
    var links: [NoteLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteHistoryEntry.page)
    var history: [NoteHistoryEntry]? = []

    /// Unified region records — each at-most-one header text +
    /// at-most-one link destination per region. The legacy `headers`
    /// + `links` arrays remain populated during the consumer
    /// migration; new code writes through `regions` only.
    @Relationship(deleteRule: .cascade, inverse: \NoteRegion.page)
    var regions: [NoteRegion]? = []

    init(
        id: UUID = UUID(),
        index: Int = 0,
        createdAt: Date = Date(),
        templateName: String = CanvasTemplate.none.rawValue,
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.index = index
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.templateName = templateName
        self.notebook = notebook
    }
}
