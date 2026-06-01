import Foundation
import CoreGraphics

/// Value-type projection of `PDFAnnotation` — anchored to a
/// `PDFDocument` via `pdfDocumentID`. `bounds` is normalized 0..1
/// within the PDF page so it survives re-rendering at any scale.
///
/// `pdfDocumentID` is optional: a fetched annotation with a nil parent
/// relationship is an orphan (sync race, corrupt store) and consumers
/// should treat the missing parent as a genuine signal — not be fed
/// a fabricated UUID that looks like a real reference but silently
/// misses on lookup.
///
/// `hasInkData` / `hasPencilDrawing` are presence flags; the
/// `inkDataByteSize` / `pencilDrawingByteSize` siblings expose payload
/// magnitude without materializing the bytes (the snapshot stays
/// lightweight enough to ride through a TCA state tree). Consumers
/// that need the actual bytes round-trip via the model.
struct PDFAnnotationSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pdfDocumentID: UUID?
    let kind: AnnotationKind
    let createdAt: Date
    let modifiedAt: Date
    let pageIndex: Int
    let extractedText: String
    let contents: String
    let bounds: CGRect
    let color: PDFAnnotationColor
    let hasInkData: Bool
    let inkDataByteSize: Int?
    let hasPencilDrawing: Bool
    let pencilDrawingByteSize: Int?
}

// MARK: - Conversion from @Model

extension PDFAnnotationSnapshot {
    init(model: PDFAnnotation) {
        self.id = model.id
        self.pdfDocumentID = model.pdfDocument?.id
        self.kind = model.kind
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.pageIndex = model.pageIndex
        self.extractedText = model.extractedText
        self.contents = model.contents
        self.bounds = model.bounds
        self.color = model.color
        self.hasInkData = model.inkData != nil
        self.inkDataByteSize = model.inkData?.count
        self.hasPencilDrawing = model.pencilDrawing != nil
        self.pencilDrawingByteSize = model.pencilDrawing?.count
    }
}
