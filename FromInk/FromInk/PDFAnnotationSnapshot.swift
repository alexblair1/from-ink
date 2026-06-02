import Foundation
import CoreGraphics

/// Value-type projection of `PDFAnnotation` — anchored to a
/// `ImportedPDF` via `pdfDocumentID`. `bounds` is normalized 0..1
/// within the PDF page so it survives re-rendering at any scale.
///
/// `pdfDocumentID` is optional: a fetched annotation with a nil parent
/// relationship is an orphan (sync race, corrupt store) and consumers
/// should treat the missing parent as a genuine signal — not be fed
/// a fabricated UUID that looks like a real reference but silently
/// misses on lookup.
///
/// `inkData` is held back from the snapshot — PDFKit raw ink isn't
/// rendered today (Phase 4 / 5 render via `.highlight`, `.underline`,
/// and `.pencil`). `hasInkData` + `inkDataByteSize` expose presence
/// and magnitude.
///
/// `pencilDrawing` **is** carried on the snapshot for
/// `kind == .pencil` records because the reconcile loop needs the
/// bytes to deserialize the `PKDrawing` and render its strokes as
/// PDFKit `.ink` paths. Pencil snapshots are heavier than other
/// kinds by design — typical drawings are 10–100KB, which fits
/// comfortably in a TCA state tree.
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
    /// `PKDrawing.dataRepresentation()` bytes for `.pencil` records;
    /// nil for all other kinds. Carried on the snapshot so the
    /// reconcile loop can render without re-fetching the model.
    let pencilDrawing: Data?
}

// MARK: - Derived accessors

extension PDFAnnotationSnapshot {
    var hasPencilDrawing: Bool { pencilDrawing != nil }
    var pencilDrawingByteSize: Int? { pencilDrawing?.count }
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
        self.pencilDrawing = model.pencilDrawing
    }
}
