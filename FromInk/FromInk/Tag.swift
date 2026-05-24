import Foundation
import SwiftData

/// User-defined tag applied to notebooks. Many-to-many — the
/// `@Relationship(inverse: \Tag.notebooks)` macro is declared on
/// `Notebook.tags` (the parent side) only; here we just hold the back-
/// pointer array. Declaring `@Relationship` on both sides would trigger
/// SwiftData's "duplicate inverse" runtime error.
@Model final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#1A1A1A"
    var createdAt: Date = Date()

    var notebooks: [Notebook]? = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#1A1A1A",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}
