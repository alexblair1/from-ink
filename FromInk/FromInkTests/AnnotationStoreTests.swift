import ComposableArchitecture
import CoreGraphics
import PencilKit
import SwiftData
import XCTest
@testable import FromInk

/// Integration tests for `AnnotationStore.liveValue` against an
/// in-memory SwiftData container. Verifies the round-trip
/// (create → list → snapshot equality) plus the error path
/// (`pdfNotFound`) and the no-op delete-on-missing.
///
/// The live store is constructed by overriding `syncedModelContext`
/// to point at a fresh in-memory container per test; this exercises
/// the real `ModelContext.fetch` / `insert` / `save` chain rather
/// than a stubbed version.
final class AnnotationStoreTests: XCTestCase {

    private let pdfID = UUID()
    private let bounds = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    /// Builds the `AnnotationStore.liveValue` wired to a fresh in-memory
    /// container. Inserts a single parent `ImportedPDF` so creates can
    /// resolve the relationship. Returns the store, the
    /// `SyncedModelContextDependency`, and the parent's id.
    @MainActor
    private func makeStore() -> (AnnotationStore, SyncedModelContextDependency) {
        let dep = SyncedModelContextDependency.inMemory()
        let ctx = dep.context()
        let pdf = ImportedPDF(
            id: pdfID,
            title: "Test PDF",
            contentHash: "abc",
            pageCount: 5,
            byteSize: 1024,
            createdAt: now
        )
        ctx.insert(pdf)
        try! ctx.save()

        // `AnnotationStore.liveValue` reaches for the dependency via
        // `@Dependency`. Override the global dependency for this test.
        let store = withDependencies {
            $0.syncedModelContext = dep
        } operation: {
            AnnotationStore.liveValue
        }
        return (store, dep)
    }

    // MARK: - Create round-trip

    @MainActor
    func test_createHighlight_thenList_roundTripsTheSnapshot() async throws {
        let (store, _) = makeStore()

        let created = try await store.createHighlight(
            pdfID, 3, bounds, "matched line", .yellowHighlight, now
        )

        XCTAssertEqual(created.pdfDocumentID, pdfID)
        XCTAssertEqual(created.kind, .highlight)
        XCTAssertEqual(created.pageIndex, 3)
        XCTAssertEqual(created.extractedText, "matched line")
        XCTAssertEqual(created.color, .yellowHighlight)
        XCTAssertEqual(created.bounds, bounds)

        let listed = try await store.listForPDF(pdfID)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first, created)
    }

    @MainActor
    func test_listForPDF_ordersByCreatedAtAscending() async throws {
        let (store, _) = makeStore()

        let first = try await store.createHighlight(
            pdfID, 0, bounds, "first", .yellowHighlight, now
        )
        let second = try await store.createHighlight(
            pdfID, 1, bounds, "second", .yellowHighlight, now.addingTimeInterval(60)
        )
        let third = try await store.createHighlight(
            pdfID, 2, bounds, "third", .yellowHighlight, now.addingTimeInterval(120)
        )

        let listed = try await store.listForPDF(pdfID)
        XCTAssertEqual(listed.map(\.id), [first.id, second.id, third.id])
    }

    @MainActor
    func test_listForPDF_emptyForNeverAnnotatedPDF() async throws {
        let (store, _) = makeStore()
        let listed = try await store.listForPDF(pdfID)
        XCTAssertTrue(listed.isEmpty)
    }

    // MARK: - Failure paths

    @MainActor
    func test_createHighlight_unknownPDF_throwsPdfNotFound() async {
        let (store, _) = makeStore()
        let strangerID = UUID()

        do {
            _ = try await store.createHighlight(
                strangerID, 0, bounds, "", .yellowHighlight, now
            )
            XCTFail("Expected pdfNotFound but createHighlight succeeded")
        } catch let error as AnnotationStoreError {
            XCTAssertEqual(error, .pdfNotFound(pdfID: strangerID))
        } catch {
            XCTFail("Expected AnnotationStoreError, got \(error)")
        }
    }

    // MARK: - Pencil

    @MainActor
    func test_createPencil_thenList_roundTripsTheBytesOnSnapshot() async throws {
        let (store, _) = makeStore()
        // A minimal PKDrawing — empty strokes is enough to verify the
        // bytes round-trip; the bezier-path conversion is exercised
        // separately in PDFCanvas tests.
        let drawing = PKDrawing()
        let drawingBytes = drawing.dataRepresentation()

        let created = try await store.createPencil(
            pdfID, 2, bounds, drawingBytes, .blackText, now
        )

        XCTAssertEqual(created.kind, .pencil)
        XCTAssertEqual(created.pageIndex, 2)
        XCTAssertEqual(created.bounds, bounds)
        XCTAssertEqual(created.pencilDrawing, drawingBytes)
        XCTAssertTrue(created.hasPencilDrawing)
        XCTAssertEqual(created.pencilDrawingByteSize, drawingBytes.count)

        let listed = try await store.listForPDF(pdfID)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.pencilDrawing, drawingBytes)
    }

    @MainActor
    func test_createPencil_unknownPDF_throwsPdfNotFound() async {
        let (store, _) = makeStore()
        let strangerID = UUID()
        let drawing = PKDrawing().dataRepresentation()

        do {
            _ = try await store.createPencil(
                strangerID, 0, bounds, drawing, .blackText, now
            )
            XCTFail("Expected pdfNotFound but createPencil succeeded")
        } catch let error as AnnotationStoreError {
            XCTAssertEqual(error, .pdfNotFound(pdfID: strangerID))
        } catch {
            XCTFail("Expected AnnotationStoreError, got \(error)")
        }
    }

    // MARK: - Delete

    @MainActor
    func test_delete_removesTheAnnotation() async throws {
        let (store, _) = makeStore()
        let created = try await store.createHighlight(
            pdfID, 0, bounds, "doomed", .yellowHighlight, now
        )

        let beforeDelete = try await store.listForPDF(pdfID)
        XCTAssertEqual(beforeDelete.count, 1)

        try await store.delete(created.id)
        let afterDelete = try await store.listForPDF(pdfID)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    /// Deleting an annotation that's already gone is a no-op — the
    /// most common failure mode is a sync race and re-throwing would
    /// mask the real cause.
    @MainActor
    func test_delete_missingAnnotation_isNoOp() async throws {
        let (store, _) = makeStore()
        try await store.delete(UUID())
        // No throw, no state change.
    }

    /// Cascade-delete: removing the parent PDF should remove its
    /// annotations via the `@Relationship(deleteRule: .cascade)` on
    /// `ImportedPDF.annotations`. Verifying here so a future schema
    /// change that breaks the cascade is caught immediately.
    @MainActor
    func test_deletingParentPDF_cascadeRemovesAnnotations() async throws {
        let (store, dep) = makeStore()
        _ = try await store.createHighlight(
            pdfID, 0, bounds, "doomed", .yellowHighlight, now
        )

        let ctx = dep.context()
        let descriptor = FetchDescriptor<ImportedPDF>(
            predicate: #Predicate { $0.id == pdfID }
        )
        guard let pdf = try ctx.fetch(descriptor).first else {
            XCTFail("Parent PDF should exist")
            return
        }
        ctx.delete(pdf)
        try ctx.save()

        let afterCascade = try await store.listForPDF(pdfID)
        XCTAssertTrue(afterCascade.isEmpty)
    }
}
