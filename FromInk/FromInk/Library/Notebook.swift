import SwiftData
import Foundation

@Model final class Notebook {
    var id: UUID
    var title: String
    var createdAt: Date
    var lastOpenedAt: Date
    var coverColorHex: String
    var folderID: UUID?

    init(
        title: String = "Untitled",
        coverColorHex: String = "#141414",
        folderID: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.lastOpenedAt = Date()
        self.coverColorHex = coverColorHex
        self.folderID = folderID
    }
}
