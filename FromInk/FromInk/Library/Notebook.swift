import Foundation
import SwiftData

/// A notebook — the top-level user document. Notebooks contain ordered
/// pages, may live inside a folder, and may carry tags and PDF
/// highlights. The `documentKind` discriminator distinguishes the four
/// variants (notebook / quickSheet / pdfDocument / textNote); ink-bearing
/// kinds use the `pages` relationship, while `pdfDocument` additionally
/// owns `highlights` anchored to PDF page indices.
///
/// **CloudKit notes:**
/// - Every property has a default (CloudKit silent-failure prevention).
/// - All relationships optional; `@Relationship(...)` declared on this
///   parent side only — child classes (`NotePage`, `Highlight`, `Tag`)
///   hold plain back-pointers without a macro to avoid SwiftData's
///   "duplicate inverse" runtime error.
/// - `sourcePDFData` uses `@Attribute(.externalStorage)` so payloads
///   larger than CloudKit's 1 MB record limit auto-promote to `CKAsset`.
/// - `#Predicate` cannot read computed properties — predicates on
///   document kind must reference `documentKindRaw == "quickSheet"`.
@Model final class Notebook {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var coverColorHex: String = "#FAFAF8"
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0

    var documentKindRaw: String = DocumentKind.notebook.rawValue
    var documentKind: DocumentKind {
        get { DocumentKind(rawValue: documentKindRaw) ?? .notebook }
        set { documentKindRaw = newValue.rawValue }
    }

    @Attribute(.externalStorage)
    var sourcePDFData: Data?

    // Parent
    var folder: Folder?

    // Children
    @Relationship(deleteRule: .cascade, inverse: \NotePage.notebook)
    var pages: [NotePage]? = []

    @Relationship(inverse: \Tag.notebooks)
    var tags: [Tag]? = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.notebook)
    var highlights: [Highlight]? = []

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        kind: DocumentKind = .notebook,
        coverColorHex: String = "#FAFAF8",
        folder: Folder? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        // Default `modifiedAt` to `createdAt` so a freshly minted notebook
        // reads as "modified now" without callers having to supply both.
        // Backfill / import flows that need a distinct value (e.g.,
        // restoring a notebook last edited yesterday) pass it explicitly.
        self.modifiedAt = modifiedAt ?? createdAt
        self.documentKindRaw = kind.rawValue
        self.coverColorHex = coverColorHex
        self.folder = folder
        self.sortOrder = sortOrder
    }
}
