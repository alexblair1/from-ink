import Foundation
import CoreGraphics
import SwiftData

/// Annotation belonging to a `PDFDocument`. Anchors to a PDF page
/// index rather than a `NotePage` because PDF pages don't have stable
/// `NotePage` model identities.
///
/// The bounding box is stored as four normalized (0..1) `Double` fields
/// so the position survives re-rendering the PDF at any scale or zoom
/// level. Color is stored as four `Double` primitives (R/G/B/A) — same
/// CloudKit-friendly pattern, no JSON encoding overhead on each read.
///
/// **Construction.** Prefer the kind-specific factory methods below
/// (`.highlight(...)`, `.ink(...)`, etc.) — they enforce the per-kind
/// payload invariant by signature. The raw `init` exists for SwiftData
/// model identity and is **not** the recommended construction path; it
/// permits all field combinations and the resulting record may fail
/// `validatePayload()`.
///
/// **Mutation contract.** All mutations go through `AnnotationStore`
/// (forthcoming). The store is responsible for bumping `modifiedAt`
/// via `CalendarContext.now()` on every write. Direct property
/// assignment on a fetched `PDFAnnotation` will **not** automatically
/// update `modifiedAt`, breaking CloudKit's last-writer-wins conflict
/// resolution. There's no `didSet` observer on `modifiedAt` because
/// the dates EDD bans bare `Date()` outside `CalendarContext.liveValue`
/// — the property observer can't reach the calendar dependency.
/// Enforcement is code-review discipline, not compiler-enforced.
///
/// **Payload by kind:**
/// - `.highlight` / `.underline` — bounds + color; `extractedText`
///   carries the matched text.
/// - `.freeText` — bounds + color; `contents` carries the note body.
/// - `.line` / `.square` / `.circle` — bounds + color only.
/// - `.polygon` — bounds + color; `inkData` carries the vertex bezier
///   path (PDF polygons share the bezier payload shape with `.ink`).
/// - `.ink` — bounds (stroke union) + color; `inkData` carries
///   serialized bezier paths (PDFKit `.ink` primitive).
/// - `.pencil` — bounds (drawing extent) + color; `pencilDrawing`
///   carries `PKDrawing.dataRepresentation()` bytes.
@Model final class PDFAnnotation {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Annotation kind discriminator. Stored as raw String for CloudKit;
    /// exposed via the computed `kind` bridge below. Defaults to
    /// `.highlight` so a row created without an explicit kind reads as
    /// a highlight rather than crashing the rendering pipeline.
    var kindRaw: String = AnnotationKind.highlight.rawValue

    var pageIndex: Int = 0
    var extractedText: String = ""
    var contents: String = ""

    // Normalized 0..1 bounding box on the PDF page
    var boundsX: Double = 0
    var boundsY: Double = 0
    var boundsWidth: Double = 0
    var boundsHeight: Double = 0

    // Color (R/G/B/A as four Doubles — no JSON, no hex string, no
    // externalStorage). Default = translucent yellow highlight (the
    // most common annotation), so a row constructed without an
    // explicit color reads as a usable highlight rather than an
    // invisible opaque-black smudge.
    var colorR: Double = PDFAnnotationColor.yellowHighlight.r
    var colorG: Double = PDFAnnotationColor.yellowHighlight.g
    var colorB: Double = PDFAnnotationColor.yellowHighlight.b
    var colorA: Double = PDFAnnotationColor.yellowHighlight.a

    /// Serialized PDFKit `.ink` annotation path data. Populated only
    /// when `kind == .ink`. externalStorage because complex hand-drawn
    /// ink can exceed the per-record limit; trivial highlights leave
    /// this nil so no asset is created.
    @Attribute(.externalStorage)
    var inkData: Data?

    /// `PKDrawing.dataRepresentation()` bytes. Populated only when
    /// `kind == .pencil`. PencilKit drawing data is dense — multi-stroke
    /// pages easily clear 100 KB; externalStorage avoids inflating the
    /// record body.
    @Attribute(.externalStorage)
    var pencilDrawing: Data?

    /// CloudKit record ID of the annotation's author. Placeholder for
    /// shared PDFs — nil today (single-user). Cheap to add now,
    /// expensive to retrofit later.
    var authorUserID: String?

    var pdfDocument: PDFDocument?

    /// **Internal — prefer the kind-specific factories.** This init
    /// permits all field combinations (including `kind = .highlight`
    /// with `inkData` set, which is logically broken). SwiftData
    /// requires an init signature shaped like this for model identity;
    /// callers should reach for `.highlight(...)`, `.ink(...)`, etc.
    init(
        id: UUID = UUID(),
        kind: AnnotationKind = .highlight,
        extractedText: String = "",
        pageIndex: Int = 0,
        contents: String = "",
        bounds: CGRect = .zero,
        color: PDFAnnotationColor = .yellowHighlight,
        createdAt: Date = Date(),
        pdfDocument: PDFDocument? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.extractedText = extractedText
        self.pageIndex = pageIndex
        self.contents = contents
        self.boundsX = Double(bounds.origin.x)
        self.boundsY = Double(bounds.origin.y)
        self.boundsWidth = Double(bounds.size.width)
        self.boundsHeight = Double(bounds.size.height)
        self.colorR = color.r
        self.colorG = color.g
        self.colorB = color.b
        self.colorA = color.a
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.pdfDocument = pdfDocument
    }

    /// Annotation kind. Falls back to `.highlight` if the raw value is
    /// somehow unrecognized (corruption / cross-version sync race).
    var kind: AnnotationKind {
        get { AnnotationKind(rawValue: kindRaw) ?? .highlight }
        set { kindRaw = newValue.rawValue }
    }

    var bounds: CGRect {
        CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight)
    }

    var color: PDFAnnotationColor {
        PDFAnnotationColor(r: colorR, g: colorG, b: colorB, a: colorA)
    }

    /// Validates the per-kind payload invariant. Throws if the record
    /// shape is logically broken (e.g. `kind == .highlight` with
    /// `inkData` populated). Call before persisting from any path
    /// that doesn't go through the factories; the upcoming
    /// `AnnotationStore` will run this on every create/update.
    func validatePayload() throws {
        let hasInk = inkData != nil
        let hasPencil = pencilDrawing != nil
        switch kind {
        case .highlight, .underline, .freeText, .line, .square, .circle:
            // Geometry-only kinds: no path/drawing payload.
            guard !hasInk, !hasPencil else {
                throw PDFAnnotationValidationError.unexpectedPayload(
                    kind: kind, hasInkData: hasInk, hasPencilDrawing: hasPencil
                )
            }
        case .polygon, .ink:
            // Both carry bezier path data in `inkData`. `.polygon` is
            // a PDF subtype that shares ink's path payload; the
            // distinction is purely the rendering subtype string.
            guard hasInk, !hasPencil else {
                throw PDFAnnotationValidationError.unexpectedPayload(
                    kind: kind, hasInkData: hasInk, hasPencilDrawing: hasPencil
                )
            }
        case .pencil:
            guard hasPencil, !hasInk else {
                throw PDFAnnotationValidationError.unexpectedPayload(
                    kind: kind, hasInkData: hasInk, hasPencilDrawing: hasPencil
                )
            }
        }
    }
}

// MARK: - Factories (preferred construction path)

extension PDFAnnotation {
    /// A highlighted text region. Bounds frame the text run.
    static func highlight(
        pageIndex: Int,
        bounds: CGRect,
        extractedText: String = "",
        color: PDFAnnotationColor = .yellowHighlight,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        PDFAnnotation(
            kind: .highlight,
            extractedText: extractedText,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
    }

    /// An underlined text region. Bounds frame the text run.
    static func underline(
        pageIndex: Int,
        bounds: CGRect,
        extractedText: String = "",
        color: PDFAnnotationColor = .yellowHighlight,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        PDFAnnotation(
            kind: .underline,
            extractedText: extractedText,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
    }

    /// A typed text note placed at a point on the page.
    static func freeText(
        pageIndex: Int,
        bounds: CGRect,
        contents: String,
        color: PDFAnnotationColor = .blackText,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        PDFAnnotation(
            kind: .freeText,
            pageIndex: pageIndex,
            contents: contents,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
    }

    /// A straight line annotation. Bounds frame the endpoints'
    /// bounding box.
    static func line(
        pageIndex: Int,
        bounds: CGRect,
        color: PDFAnnotationColor,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        PDFAnnotation(
            kind: .line,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
    }

    /// A rectangle outline. Bounds frame the rectangle.
    static func square(
        pageIndex: Int,
        bounds: CGRect,
        color: PDFAnnotationColor,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        PDFAnnotation(
            kind: .square,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
    }

    /// An oval outline. Bounds frame the oval's bounding rectangle.
    static func circle(
        pageIndex: Int,
        bounds: CGRect,
        color: PDFAnnotationColor,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        PDFAnnotation(
            kind: .circle,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
    }

    /// A closed polygon outline. Vertex data carried in `inkData`
    /// (PDF polygons share the bezier path payload with `.ink`).
    static func polygon(
        pageIndex: Int,
        bounds: CGRect,
        color: PDFAnnotationColor,
        vertexData: Data,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        let annotation = PDFAnnotation(
            kind: .polygon,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
        annotation.inkData = vertexData
        return annotation
    }

    /// A PDFKit `.ink` annotation — bezier paths in `inkData`.
    static func ink(
        pageIndex: Int,
        bounds: CGRect,
        color: PDFAnnotationColor,
        inkData: Data,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        let annotation = PDFAnnotation(
            kind: .ink,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
        annotation.inkData = inkData
        return annotation
    }

    /// A PencilKit overlay — `PKDrawing.dataRepresentation()` bytes in
    /// `pencilDrawing`. Color tracks the dominant stroke color for UI
    /// hints; the drawing itself carries its own per-stroke colors.
    static func pencil(
        pageIndex: Int,
        bounds: CGRect,
        pencilDrawing: Data,
        color: PDFAnnotationColor = .blackText,
        createdAt: Date,
        pdfDocument: PDFDocument? = nil
    ) -> PDFAnnotation {
        let annotation = PDFAnnotation(
            kind: .pencil,
            pageIndex: pageIndex,
            bounds: bounds,
            color: color,
            createdAt: createdAt,
            pdfDocument: pdfDocument
        )
        annotation.pencilDrawing = pencilDrawing
        return annotation
    }
}

// MARK: - Color

/// Value-type color for `PDFAnnotation`. R/G/B/A as four normalized
/// Doubles (0..1). Stored on the model as four primitive fields rather
/// than encoded — avoids JSON parse overhead on every property access
/// and keeps the CloudKit record body simple.
struct PDFAnnotationColor: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    /// Translucent yellow — the canonical highlight tint. Default for
    /// `.highlight` / `.underline` factories.
    static let yellowHighlight = PDFAnnotationColor(r: 1, g: 0.9, b: 0.2, a: 0.35)

    /// Opaque black — typical for text and shape annotations.
    static let blackText = PDFAnnotationColor(r: 0, g: 0, b: 0, a: 1)
}

// MARK: - Validation

enum PDFAnnotationValidationError: Error, Equatable, Sendable {
    /// A payload field is set that doesn't match the annotation kind
    /// (e.g. `kind == .highlight` with `inkData` populated, or
    /// `kind == .pencil` with no `pencilDrawing`).
    case unexpectedPayload(kind: AnnotationKind, hasInkData: Bool, hasPencilDrawing: Bool)
}
