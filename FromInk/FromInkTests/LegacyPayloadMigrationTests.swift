import ComposableArchitecture
import Foundation
import SwiftData
import XCTest
@testable import FromInk

/// Integration coverage for the Phase 2a ink cutover
/// (hybrid_page_edd §6 Phase 2) against the live NotebookClient with
/// an in-memory SwiftData store:
///
///   • Legacy page-level payloads (`drawingData` / `ocrText` /
///     `typedText`) migrate into `PageBlock`s on the first
///     `fetchBlocksForPage`, and the legacy fields clear — read
///     legacy → write block → clear legacy, idempotently.
///   • `updateBlockDrawing` mirrors the ink thumbnail onto the
///     page-card projection the library grid reads.
///   • `bindCanonicalCanvasWidth` binds exactly once per notebook.
final class LegacyPayloadMigrationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @MainActor
    private func makeClient() -> (NotebookClient, SyncedModelContextDependency) {
        let ctx = SyncedModelContextDependency.inMemory()
        let client = NotebookClient.live(
            modelContext: ctx,
            calendarContext: CalendarContext.fixed(now: now)
        )
        return (client, ctx)
    }

    @MainActor
    private func seedNotebookPage(
        context modelContext: SyncedModelContextDependency
    ) throws -> (notebook: Notebook, page: NotePage) {
        let ctx = modelContext.context()
        let notebook = Notebook(title: "Test", createdAt: now, modifiedAt: now)
        ctx.insert(notebook)
        let page = NotePage(notebook: notebook)
        page.modifiedAt = now
        ctx.insert(page)
        try ctx.save()
        return (notebook, page)
    }

    // MARK: - Ink payload migration

    @MainActor
    func test_fetchBlocksForPage_migratesLegacyDrawing_andClearsLegacyFields() async throws {
        let (client, ctx) = makeClient()
        let (_, page) = try seedNotebookPage(context: ctx)
        let inkBytes = Data("legacy-ink-payload".utf8)
        let thumbBytes = Data("legacy-thumb".utf8)
        page.drawingData = inkBytes
        page.thumbnailData = thumbBytes
        page.ocrText = "Meeting notes Friday"
        page.ocrUpdatedAt = now
        try ctx.context().save()
        let pageID = page.id

        let blocks = try await client.fetchBlocksForPage(pageID)

        XCTAssertEqual(blocks.count, 1)
        let ink = try XCTUnwrap(blocks.first(where: { $0.kind == .ink }))
        XCTAssertEqual(ink.ocrText, "Meeting notes Friday")
        let movedDrawing = try await client.loadBlockDrawing(ink.id)
        XCTAssertEqual(movedDrawing, inkBytes, "Ink bytes move onto the block verbatim")

        // Legacy payloads cleared; the page-card thumbnail SURVIVES
        // (the library grid reads it).
        XCTAssertNil(page.drawingData)
        XCTAssertNil(page.ocrText)
        XCTAssertNil(page.ocrUpdatedAt)
        XCTAssertEqual(page.thumbnailData, thumbBytes)

        // Idempotent: a second fetch neither duplicates nor mutates.
        let again = try await client.fetchBlocksForPage(pageID)
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again.first?.id, ink.id)
    }

    @MainActor
    func test_fetchBlocksForPage_existingInkBlock_staleLegacyDropsWithoutDuplicate() async throws {
        let (client, ctx) = makeClient()
        let (_, page) = try seedNotebookPage(context: ctx)
        let pageID = page.id

        // A real ink block already exists (post-cutover save)...
        let existing = try await client.insertBlock(pageID, .ink, nil)
        try await client.updateBlockDrawing(existing.id, Data("current-ink".utf8), nil)
        // ...and stale legacy bytes linger from before the cutover.
        page.drawingData = Data("stale-legacy-ink".utf8)
        try ctx.context().save()

        let blocks = try await client.fetchBlocksForPage(pageID)

        XCTAssertEqual(blocks.filter { $0.kind == .ink }.count, 1, "No duplicate ink block")
        let payload = try await client.loadBlockDrawing(existing.id)
        XCTAssertEqual(payload, Data("current-ink".utf8), "The block's CURRENT ink wins")
        XCTAssertNil(page.drawingData, "Stale legacy bytes are dropped, not resurrected")
    }

    // MARK: - Typed-text migration

    @MainActor
    func test_fetchBlocksForPage_migratesTypedText_intoTextBlockDocument() async throws {
        let (client, ctx) = makeClient()
        let (_, page) = try seedNotebookPage(context: ctx)
        page.typedText = "Pre-block typed note"
        try ctx.context().save()
        let pageID = page.id

        let blocks = try await client.fetchBlocksForPage(pageID)

        let text = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        XCTAssertEqual(text.plainText, "Pre-block typed note")
        let document = try XCTUnwrap(text.document)
        XCTAssertEqual(document.plainText, "Pre-block typed note")
        XCTAssertNil(page.typedText)
    }

    @MainActor
    func test_fetchBlocksForPage_freshPage_migratesNothing() async throws {
        let (client, ctx) = makeClient()
        let (_, page) = try seedNotebookPage(context: ctx)

        let blocks = try await client.fetchBlocksForPage(page.id)

        XCTAssertTrue(blocks.isEmpty, "No legacy payload → no synthesized blocks")
    }

    // MARK: - Page-card thumbnail mirror

    @MainActor
    func test_updateBlockDrawing_mirrorsThumbnailToPageCard() async throws {
        let (client, ctx) = makeClient()
        let (_, page) = try seedNotebookPage(context: ctx)
        let block = try await client.insertBlock(page.id, .ink, nil)

        let thumb = Data("fresh-thumbnail".utf8)
        try await client.updateBlockDrawing(block.id, Data("ink".utf8), thumb)

        XCTAssertEqual(
            page.thumbnailData, thumb,
            "The library grid's page card mirrors the latest ink save"
        )
    }

    // MARK: - Canonical width binding

    @MainActor
    func test_bindCanonicalCanvasWidth_bindsOnce() async throws {
        let (client, ctx) = makeClient()
        let (notebook, _) = try seedNotebookPage(context: ctx)

        try await client.bindCanonicalCanvasWidth(notebook.id, 834)
        XCTAssertEqual(notebook.canonicalCanvasWidth, 834)
        XCTAssertTrue(notebook.canonicalCanvasWidthIsBound)

        // Second bind (rotation, another device's width) is a no-op —
        // the canonical width is one-way.
        try await client.bindCanonicalCanvasWidth(notebook.id, 1194)
        XCTAssertEqual(notebook.canonicalCanvasWidth, 834)
    }
}
