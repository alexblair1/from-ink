import Foundation

/// Value-type projection of `Folder` for the library sidebar / picker.
/// `parentID` is the parent folder's UUID (nil = root). Children are not
/// pre-flattened here — load them via a separate fetch if needed; the
/// EDD limits folder depth to two levels in app logic, so most callers
/// can ignore nesting and just bucket by `parentID`.
struct FolderSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let sortOrder: Int
    let parentID: UUID?
    let notebookCount: Int
}

// MARK: - Conversion from @Model

extension FolderSnapshot {
    init(model: Folder) {
        self.id = model.id
        self.name = model.name
        self.createdAt = model.createdAt
        self.sortOrder = model.sortOrder
        self.parentID = model.parent?.id
        self.notebookCount = model.notebooks?.count ?? 0
    }
}
