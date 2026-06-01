import Foundation
import SwiftData

/// A user-defined folder that groups notebooks and PDFs. Self-referencing
/// parent pointer supports two-level nesting; the depth limit is enforced
/// in app logic (`NotebookClient.createFolder` rejects depth > 1).
///
/// **Delete behavior:** deleting a folder cascades to its child folders
/// (`.cascade`) but nullifies its notebooks and PDFs (`.nullify`) — both
/// outlive their folder, returning to the root list rather than
/// disappearing with the container.
@Model final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder]? = []

    @Relationship(deleteRule: .nullify, inverse: \Notebook.folder)
    var notebooks: [Notebook]? = []

    /// Imported PDFs in this folder. Same `.nullify` rule as
    /// `notebooks` — deleting a folder returns its PDFs to the root,
    /// not the bin. Without this inverse, `ImportedPDF.folder` would
    /// be a dangling back-pointer with undefined cascade behavior.
    @Relationship(deleteRule: .nullify, inverse: \ImportedPDF.folder)
    var pdfs: [ImportedPDF]? = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        parent: Folder? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.parent = parent
    }
}
