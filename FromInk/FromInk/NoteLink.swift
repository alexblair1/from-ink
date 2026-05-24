import Foundation
import CoreGraphics
import SwiftData

/// A lasso-selected region of ink flagged as a tappable link. Cross-notebook
/// references use `targetPageID` / `targetNotebookID` UUIDs rather than
/// SwiftData relationships — deleting the target notebook leaves a broken
/// link (graceful) rather than cascade-deleting the source page
/// (catastrophic). See `data_model_edd.md` §4.7.
///
/// Exactly one of `externalURL`, `targetPageID`, `targetNotebookID` is
/// non-nil in any valid persisted state. The `NotebookClient` enforces
/// this via the closed `NoteLinkDestination` enum at the API boundary;
/// the model layer permits all three for CloudKit-friendly optional storage.
@Model final class NoteLink {
    var id: UUID = UUID()
    var ocrText: String = ""
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0
    var createdAt: Date = Date()

    // Destination — exactly one is non-nil
    var externalURL: String?
    var targetPageID: UUID?
    var targetNotebookID: UUID?

    var page: NotePage?

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        ocrText: String = "",
        rect: CGRect,
        createdAt: Date = Date(),
        externalURL: String? = nil,
        targetPageID: UUID? = nil,
        targetNotebookID: UUID? = nil
    ) {
        self.id = id
        self.page = page
        self.ocrText = ocrText
        self.rectX = Double(rect.origin.x)
        self.rectY = Double(rect.origin.y)
        self.rectWidth = Double(rect.size.width)
        self.rectHeight = Double(rect.size.height)
        self.createdAt = createdAt
        self.externalURL = externalURL
        self.targetPageID = targetPageID
        self.targetNotebookID = targetNotebookID
    }

    var rect: CGRect {
        CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
    }
}
