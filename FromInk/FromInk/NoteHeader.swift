import Foundation
import CoreGraphics
import SwiftData

/// A lasso-selected region of ink flagged as a section header. The
/// bounding rect is stored as four `Double` fields (CloudKit-friendly
/// scalars) and projected through the computed `rect` property.
///
/// Headers belong to a single `NotePage`; the parent declares the
/// cascade-delete relationship via `@Relationship(deleteRule: .cascade,
/// inverse: \NoteHeader.page)` on `NotePage.headers`.
@Model final class NoteHeader {
    var id: UUID = UUID()
    var ocrText: String = ""
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    var page: NotePage?

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        ocrText: String = "",
        rect: CGRect,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.page = page
        self.ocrText = ocrText
        self.rectX = Double(rect.origin.x)
        self.rectY = Double(rect.origin.y)
        self.rectWidth = Double(rect.size.width)
        self.rectHeight = Double(rect.size.height)
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    var rect: CGRect {
        CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
    }
}
