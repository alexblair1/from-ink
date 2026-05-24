import Foundation
import SwiftData

/// A single page inside a `Notebook`. Pages are the unit of lazy loading —
/// `drawingData` and `thumbnailData` are marked `@Attribute(.externalStorage)`
/// so SwiftData stores them off-row and CloudKit promotes them to `CKAsset`
/// on sync (avoiding the 1 MB per-record limit).
///
/// **Lifecycle responsibilities (deferred to `NotebookClient`):**
/// - Reindexing siblings after `transferPage(to:at:)`
/// - Updating `Notebook.modifiedAt` when any page mutates
/// - Cascade-deleting `headers` / `links` / `history` via the inverse
///   relationship declared on this class (when Step 3 rewrites `Notebook`,
///   the parent-side `@Relationship(deleteRule: .cascade, ...)` macro
///   lands there)
///
/// The `notebook` back-pointer here is intentionally plain (no
/// `@Relationship` macro) — the macro lives on the parent side only to
/// avoid SwiftData's "duplicate inverse" runtime error.
@Model final class NotePage {
    var id: UUID = UUID()
    var index: Int = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var templateName: String = "blank"

    // Ink payload — externalStorage promotes to CKAsset on sync.
    @Attribute(.externalStorage)
    var drawingData: Data?

    @Attribute(.externalStorage)
    var thumbnailData: Data?

    // PDF page reference (populated when parent Notebook.documentKind == .pdfDocument)
    var pdfPageIndex: Int?

    // OCR
    var ocrText: String?
    var ocrUpdatedAt: Date?

    // Typed text (populated when parent Notebook.documentKind == .textNote)
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

    init(
        id: UUID = UUID(),
        index: Int = 0,
        createdAt: Date = Date(),
        templateName: String = "blank",
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
