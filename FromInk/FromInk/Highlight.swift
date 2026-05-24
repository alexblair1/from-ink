import Foundation
import CoreGraphics
import SwiftData

/// PDF annotation belonging to a `Notebook` (specifically one with
/// `documentKind == .pdfDocument`). Highlights anchor to a PDF page
/// index rather than a `NotePage` because PDF pages don't have stable
/// `NotePage` model identities.
///
/// The bounding box is stored as four normalized (0..1) `Double` fields
/// so the highlight position survives re-rendering the PDF at any scale
/// or zoom level.
@Model final class Highlight {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var pageIndex: Int = 0
    var extractedText: String = ""
    var commentary: String = ""

    // Normalized 0..1 bounding box on the PDF page
    var boundsX: Double = 0
    var boundsY: Double = 0
    var boundsWidth: Double = 0
    var boundsHeight: Double = 0

    var notebook: Notebook?

    init(
        id: UUID = UUID(),
        extractedText: String = "",
        pageIndex: Int = 0,
        commentary: String = "",
        bounds: CGRect = .zero,
        createdAt: Date = Date(),
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.extractedText = extractedText
        self.pageIndex = pageIndex
        self.commentary = commentary
        self.boundsX = Double(bounds.origin.x)
        self.boundsY = Double(bounds.origin.y)
        self.boundsWidth = Double(bounds.size.width)
        self.boundsHeight = Double(bounds.size.height)
        self.createdAt = createdAt
        self.notebook = notebook
    }

    var bounds: CGRect {
        CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight)
    }
}
