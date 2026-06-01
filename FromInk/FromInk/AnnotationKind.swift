import Foundation

/// The kind of annotation stored on a `PDFAnnotation` model.
///
/// Stored on `PDFAnnotation.kindRaw` as a raw `String` (CloudKit cannot
/// encode enums natively) and exposed via the computed
/// `PDFAnnotation.kind` bridge. `#Predicate` cannot read computed
/// properties — predicates on annotation kind must reference
/// `kindRaw == "ink"` directly.
enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    /// Highlighted text region. Bounds frame the text run on the page.
    case highlight
    /// Underlined text region. Bounds frame the text run on the page.
    case underline
    /// Typed text note placed at a point on the page.
    case freeText

    // MARK: - Shape primitives
    //
    // PDFKit splits drawn shapes into four distinct subtypes
    // (`PDFAnnotationSubtype.line` / `.square` / `.circle` /
    // `.polygon`). Modeling them as one `.shape` discriminator would
    // lose the information needed to round-trip back into a
    // `PDFAnnotation` of the right subtype — a rectangle and an oval
    // share the same bounds. Four cases, one for each PDFKit
    // primitive, keep the apply/reconstruct loop trivial.

    /// Straight line annotation. Bounds frame the endpoints' bounding
    /// box; `PDFAnnotationSubtype.line` on render.
    case line
    /// Rectangle outline. `PDFAnnotationSubtype.square` on render
    /// (PDFKit's name; not literal "square" — any rectangular bounds).
    case square
    /// Oval outline. `PDFAnnotationSubtype.circle` on render
    /// (PDFKit's name; not literal "circle" — any elliptical bounds).
    case circle
    /// Closed polygon. Multi-segment outline; vertex data carried in
    /// `inkData` because PDF polygons use the same bezier-path payload
    /// as ink annotations. `PDFAnnotationSubtype.polygon` on render.
    case polygon

    // MARK: - Stroke payloads

    /// PDFKit `.ink` annotation — bezier paths, portable PDF primitive.
    case ink
    /// PencilKit `PKDrawing` overlay. Higher fidelity than PDF `.ink`
    /// (pressure, tilt, brush type) but proprietary; flattened to
    /// `.ink` or rasterized on export.
    case pencil
}
