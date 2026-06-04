import Foundation
import SwiftData

/// A notebook — a user-created handwriting / typed document. Notebooks
/// contain ordered pages, may live inside a folder, and may carry tags.
/// The `notebookType` discriminator distinguishes the three handwriting/
/// text variants (notebook / quickSheet / textNote).
///
/// PDFs are NOT notebooks. They're their own root entity (`ImportedPDF`).
/// PDF-specific fields, annotations, and lifecycle live there.
///
/// **CloudKit notes:**
/// - Every property has a default (CloudKit silent-failure prevention).
/// - All relationships optional; `@Relationship(...)` declared on this
///   parent side only — child classes (`NotePage`, `Tag`) hold plain
///   back-pointers without a macro to avoid SwiftData's "duplicate
///   inverse" runtime error.
/// - `#Predicate` cannot read computed properties — predicates on
///   notebook type must reference `notebookTypeRaw == "quickSheet"`.
@Model final class Notebook {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var coverColorHex: String = "#FAFAF8"
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0

    var notebookTypeRaw: String = NotebookType.notebook.rawValue
    var notebookType: NotebookType {
        get { NotebookType(rawValue: notebookTypeRaw) ?? .notebook }
        set { notebookTypeRaw = newValue.rawValue }
    }

    /// CloudKit record ID of the user who created this notebook.
    /// Placeholder for future shared-notebook attribution; nil for
    /// single-user records.
    var authorUserID: String?

    // Parent
    var folder: Folder?

    // Children
    @Relationship(deleteRule: .cascade, inverse: \NotePage.notebook)
    var pages: [NotePage]? = []

    @Relationship(inverse: \Tag.notebooks)
    var tags: [Tag]? = []

    /// Calendar item links pointing at this notebook. Cascade-delete:
    /// removing a notebook removes its link records. The reverse is NOT
    /// true — deleting a link never deletes the notebook. The brief's
    /// orphan-link validator relies on this asymmetry to honor the
    /// "notebooks survive event deletion" requirement.
    @Relationship(deleteRule: .cascade, inverse: \CalendarItemLink.notebook)
    var calendarLinks: [CalendarItemLink]? = []

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        type: NotebookType = .notebook,
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
        self.notebookTypeRaw = type.rawValue
        self.coverColorHex = coverColorHex
        self.folder = folder
        self.sortOrder = sortOrder
    }
}
