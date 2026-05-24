import Foundation

/// Value-type projection of `Tag`. Tags are many-to-many with `Notebook`;
/// the snapshot does not eagerly resolve the notebook list — callers
/// that need it (e.g., "show all notebooks tagged 'work'") fetch
/// notebooks separately and filter by `tagIDs`.
struct TagSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String
    let createdAt: Date
}

// MARK: - Conversion from @Model

extension TagSnapshot {
    init(model: Tag) {
        self.id = model.id
        self.name = model.name
        self.colorHex = model.colorHex
        self.createdAt = model.createdAt
    }
}
