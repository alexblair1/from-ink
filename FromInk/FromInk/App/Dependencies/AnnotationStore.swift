import ComposableArchitecture
import CoreGraphics
import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.fromink.app", category: "AnnotationStore")

/// TCA dependency for `PDFAnnotation` CRUD. The single chokepoint for
/// SwiftData writes in the annotation domain — `PDFFeature` and the
/// upcoming highlight-creation UI dispatch through here so the
/// per-kind payload invariant (`PDFAnnotation.validatePayload`) and
/// the parent-relationship wiring stay in one place.
///
/// **Granularity:** one create-per-kind method rather than a single
/// `create(draft:)` taking a discriminated input — the per-kind
/// signatures enforce the right inputs by type. Phase 4a wires
/// `createHighlight` and `listForPDF`; ink / pencil / shape variants
/// land alongside their respective tools.
///
/// **Sync semantics:** every write calls `ctx.save()` so the
/// `NSManagedObjectContextDidSave` notification fires and
/// `LibraryFeature`'s store-change observer picks it up. Bypassing
/// `save()` would silently break the downstream refresh chain.
struct AnnotationStore: Sendable {
    /// Returns every annotation owned by the given PDF, sorted by
    /// `createdAt` ascending (oldest first — matches how
    /// `NotebookDetailSnapshot` orders its tag list). Empty array for
    /// PDFs with no annotations or PDFs that no longer exist.
    var listForPDF: @Sendable (_ pdfID: UUID) async throws -> [PDFAnnotationSnapshot]

    /// Creates a highlight annotation. `bounds` is normalized 0..1
    /// within the PDF page coordinate space. `extractedText` is the
    /// selection's textual content (PDFKit's `PDFSelection.string`).
    /// Caller passes `now` from `CalendarContext.now()` — the store
    /// never reaches for bare `Date()` per the dates EDD.
    ///
    /// Throws `AnnotationStoreError.pdfNotFound(pdfID:)` if the
    /// parent row was deleted between presentation and create. The
    /// returned snapshot is ready for immediate optimistic-render.
    var createHighlight: @Sendable (
        _ pdfID: UUID,
        _ pageIndex: Int,
        _ bounds: CGRect,
        _ extractedText: String,
        _ color: PDFAnnotationColor,
        _ now: Date
    ) async throws -> PDFAnnotationSnapshot

    /// Creates a pencil annotation — `PKDrawing.dataRepresentation()`
    /// bytes carry the strokes; `bounds` is the drawing's extent
    /// normalized 0..1 in the PDF page cropBox so the rendered
    /// annotation lines up across zoom levels.
    ///
    /// Phase 5a's read path: the reconcile loop deserializes
    /// `pencilDrawing`, converts strokes to bezier paths, and renders
    /// as a PDFKit `.ink` annotation. The original `PKDrawing` bytes
    /// stay on the record so Phase 5b's edit path can re-hydrate a
    /// `PKCanvasView` from them.
    ///
    /// Throws `AnnotationStoreError.pdfNotFound(pdfID:)` if the
    /// parent row was deleted between presentation and create.
    var createPencil: @Sendable (
        _ pdfID: UUID,
        _ pageIndex: Int,
        _ bounds: CGRect,
        _ pencilDrawing: Data,
        _ color: PDFAnnotationColor,
        _ now: Date
    ) async throws -> PDFAnnotationSnapshot

    /// Deletes an annotation by id. No-op (no throw) if the row was
    /// already gone — the most common failure mode is a sync race and
    /// re-throwing would mask the real cause.
    var delete: @Sendable (_ annotationID: UUID) async throws -> Void
}

// MARK: - Errors

enum AnnotationStoreError: Error, Equatable, Sendable {
    /// The parent PDF row no longer exists. Almost always a sync
    /// race — caller should refresh and either retry against the new
    /// PDF id or surface a "PDF was removed" message.
    case pdfNotFound(pdfID: UUID)
}

// MARK: - Live

extension AnnotationStore: DependencyKey {
    static var liveValue: AnnotationStore {
        @Dependency(\.syncedModelContext) var modelContext

        return AnnotationStore(
            listForPDF: { pdfID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<PDFAnnotation>(
                        predicate: #Predicate { $0.pdfDocument?.id == pdfID },
                        sortBy: [SortDescriptor(\.createdAt, order: .forward)]
                    )
                    return try ctx.fetch(descriptor).map(PDFAnnotationSnapshot.init(model:))
                }
            },
            createHighlight: { pdfID, pageIndex, bounds, extractedText, color, now in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let parentDescriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.id == pdfID }
                    )
                    guard let parent = try ctx.fetch(parentDescriptor).first else {
                        throw AnnotationStoreError.pdfNotFound(pdfID: pdfID)
                    }
                    let annotation = PDFAnnotation.highlight(
                        pageIndex: pageIndex,
                        bounds: bounds,
                        extractedText: extractedText,
                        color: color,
                        createdAt: now,
                        pdfDocument: parent
                    )
                    ctx.insert(annotation)
                    try ctx.save()
                    log.info("Created highlight id=\(annotation.id.uuidString, privacy: .public) pdf=\(pdfID, privacy: .public) page=\(pageIndex, privacy: .public)")
                    return PDFAnnotationSnapshot(model: annotation)
                }
            },
            createPencil: { pdfID, pageIndex, bounds, pencilDrawing, color, now in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let parentDescriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.id == pdfID }
                    )
                    guard let parent = try ctx.fetch(parentDescriptor).first else {
                        throw AnnotationStoreError.pdfNotFound(pdfID: pdfID)
                    }
                    let annotation = PDFAnnotation.pencil(
                        pageIndex: pageIndex,
                        bounds: bounds,
                        pencilDrawing: pencilDrawing,
                        color: color,
                        createdAt: now,
                        pdfDocument: parent
                    )
                    ctx.insert(annotation)
                    try ctx.save()
                    log.info("Created pencil id=\(annotation.id.uuidString, privacy: .public) pdf=\(pdfID, privacy: .public) page=\(pageIndex, privacy: .public) bytes=\(pencilDrawing.count, privacy: .public)")
                    return PDFAnnotationSnapshot(model: annotation)
                }
            },
            delete: { annotationID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<PDFAnnotation>(
                        predicate: #Predicate { $0.id == annotationID }
                    )
                    guard let annotation = try ctx.fetch(descriptor).first else {
                        // Already gone — sync race or double-delete. Not
                        // an error from the caller's perspective.
                        return
                    }
                    ctx.delete(annotation)
                    try ctx.save()
                    log.info("Deleted annotation id=\(annotationID, privacy: .public)")
                }
            }
        )
    }
}

// MARK: - Test

extension AnnotationStore: TestDependencyKey {
    /// Throwing stub — every closure throws `CancellationError`.
    /// Reducer tests override per-test via `withDependencies`.
    static let testValue = AnnotationStore(
        listForPDF: { _ in throw CancellationError() },
        createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
        createPencil: { _, _, _, _, _, _ in throw CancellationError() },
        delete: { _ in throw CancellationError() }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var annotationStore: AnnotationStore {
        get { self[AnnotationStore.self] }
        set { self[AnnotationStore.self] = newValue }
    }
}
