import CoreGraphics
import XCTest
@testable import FromInk

/// Unit coverage for `PDFAnnotation`'s per-kind factories and the
/// `validatePayload()` invariant. The factories are the recommended
/// construction path because they enforce payload shape by signature;
/// `validatePayload()` is the belt for any direct-init construction.
/// Together they guarantee a record can't carry the wrong payload
/// for its kind — these tests pin that guarantee.
final class PDFAnnotationTests: XCTestCase {

    private let bounds = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let inkData = Data([0x01, 0x02, 0x03])
    private let pencilData = Data([0xFF, 0xFE, 0xFD])

    // MARK: - Factories produce well-formed records

    func test_highlightFactory_setsKindBoundsAndDefaultColor() {
        let a = PDFAnnotation.highlight(
            pageIndex: 3,
            bounds: bounds,
            extractedText: "matched text",
            createdAt: now
        )
        XCTAssertEqual(a.kind, .highlight)
        XCTAssertEqual(a.pageIndex, 3)
        XCTAssertEqual(a.bounds, bounds)
        XCTAssertEqual(a.extractedText, "matched text")
        XCTAssertEqual(a.color, .yellowHighlight)
        XCTAssertNil(a.inkData)
        XCTAssertNil(a.pencilDrawing)
        XCTAssertEqual(a.createdAt, now)
        XCTAssertEqual(a.modifiedAt, now)
        XCTAssertNoThrow(try a.validatePayload())
    }

    func test_underlineFactory_setsKindBoundsAndDefaultColor() {
        let a = PDFAnnotation.underline(
            pageIndex: 5,
            bounds: bounds,
            createdAt: now
        )
        XCTAssertEqual(a.kind, .underline)
        XCTAssertEqual(a.color, .yellowHighlight)
        XCTAssertNil(a.inkData)
        XCTAssertNil(a.pencilDrawing)
        XCTAssertNoThrow(try a.validatePayload())
    }

    func test_freeTextFactory_storesContentsAndDefaultBlackColor() {
        let a = PDFAnnotation.freeText(
            pageIndex: 0,
            bounds: bounds,
            contents: "Sticky note body",
            createdAt: now
        )
        XCTAssertEqual(a.kind, .freeText)
        XCTAssertEqual(a.contents, "Sticky note body")
        XCTAssertEqual(a.color, .blackText)
        XCTAssertNil(a.inkData)
        XCTAssertNil(a.pencilDrawing)
        XCTAssertNoThrow(try a.validatePayload())
    }

    func test_shapeFactories_produceCorrectKindsWithoutPayload() {
        let line = PDFAnnotation.line(
            pageIndex: 0, bounds: bounds, color: .blackText, createdAt: now
        )
        XCTAssertEqual(line.kind, .line)
        XCTAssertNil(line.inkData)
        XCTAssertNoThrow(try line.validatePayload())

        let square = PDFAnnotation.square(
            pageIndex: 0, bounds: bounds, color: .blackText, createdAt: now
        )
        XCTAssertEqual(square.kind, .square)
        XCTAssertNil(square.inkData)
        XCTAssertNoThrow(try square.validatePayload())

        let circle = PDFAnnotation.circle(
            pageIndex: 0, bounds: bounds, color: .blackText, createdAt: now
        )
        XCTAssertEqual(circle.kind, .circle)
        XCTAssertNil(circle.inkData)
        XCTAssertNoThrow(try circle.validatePayload())
    }

    func test_polygonFactory_storesVertexDataInInkData() {
        let a = PDFAnnotation.polygon(
            pageIndex: 1,
            bounds: bounds,
            color: .blackText,
            vertexData: inkData,
            createdAt: now
        )
        XCTAssertEqual(a.kind, .polygon)
        XCTAssertEqual(a.inkData, inkData)
        XCTAssertNil(a.pencilDrawing)
        XCTAssertNoThrow(try a.validatePayload())
    }

    func test_inkFactory_storesPathDataInInkData() {
        let a = PDFAnnotation.ink(
            pageIndex: 2,
            bounds: bounds,
            color: .blackText,
            inkData: inkData,
            createdAt: now
        )
        XCTAssertEqual(a.kind, .ink)
        XCTAssertEqual(a.inkData, inkData)
        XCTAssertNil(a.pencilDrawing)
        XCTAssertNoThrow(try a.validatePayload())
    }

    func test_pencilFactory_storesPKDrawingBytesInPencilDrawing() {
        let a = PDFAnnotation.pencil(
            pageIndex: 4,
            bounds: bounds,
            pencilDrawing: pencilData,
            createdAt: now
        )
        XCTAssertEqual(a.kind, .pencil)
        XCTAssertEqual(a.pencilDrawing, pencilData)
        XCTAssertNil(a.inkData)
        XCTAssertNoThrow(try a.validatePayload())
    }

    // MARK: - validatePayload rejects shape-mismatched records

    /// A highlight (or any geometry-only kind) with stray `inkData` is
    /// an invalid record shape — the validator must catch it before the
    /// record reaches the renderer.
    func test_validatePayload_geometryKindWithInkData_throws() {
        let a = PDFAnnotation(kind: .highlight, pageIndex: 0)
        a.inkData = inkData
        XCTAssertThrowsError(try a.validatePayload()) { error in
            guard case let PDFAnnotationValidationError.unexpectedPayload(kind, hasInk, hasPencil) = error else {
                return XCTFail("Expected unexpectedPayload, got \(error)")
            }
            XCTAssertEqual(kind, .highlight)
            XCTAssertTrue(hasInk)
            XCTAssertFalse(hasPencil)
        }
    }

    func test_validatePayload_geometryKindWithPencilDrawing_throws() {
        let a = PDFAnnotation(kind: .square, pageIndex: 0)
        a.pencilDrawing = pencilData
        XCTAssertThrowsError(try a.validatePayload())
    }

    /// `.ink` requires `inkData`. Empty / nil is a malformed record.
    func test_validatePayload_inkKindMissingInkData_throws() {
        let a = PDFAnnotation(kind: .ink, pageIndex: 0)
        XCTAssertThrowsError(try a.validatePayload())
    }

    /// `.polygon` shares the bezier-data payload shape with `.ink` —
    /// missing `inkData` is the same kind of malformed.
    func test_validatePayload_polygonMissingInkData_throws() {
        let a = PDFAnnotation(kind: .polygon, pageIndex: 0)
        XCTAssertThrowsError(try a.validatePayload())
    }

    /// `.pencil` requires `pencilDrawing`. Missing payload is malformed.
    func test_validatePayload_pencilKindMissingDrawing_throws() {
        let a = PDFAnnotation(kind: .pencil, pageIndex: 0)
        XCTAssertThrowsError(try a.validatePayload())
    }

    /// `.pencil` must not carry `inkData` (would imply both payload
    /// types are meaningful, which violates the discriminator).
    func test_validatePayload_pencilWithInkData_throws() {
        let a = PDFAnnotation(kind: .pencil, pageIndex: 0)
        a.pencilDrawing = pencilData
        a.inkData = inkData
        XCTAssertThrowsError(try a.validatePayload())
    }

    /// `.ink` must not carry `pencilDrawing` for the same reason.
    func test_validatePayload_inkWithPencilDrawing_throws() {
        let a = PDFAnnotation(kind: .ink, pageIndex: 0)
        a.inkData = inkData
        a.pencilDrawing = pencilData
        XCTAssertThrowsError(try a.validatePayload())
    }
}
