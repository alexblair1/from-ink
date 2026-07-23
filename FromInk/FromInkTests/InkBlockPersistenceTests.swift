import ComposableArchitecture
import Foundation
import SwiftData
import XCTest
@testable import FromInk

/// Integration coverage for the Phase 2a ink persistence path
/// (hybrid_page_edd §6 Phase 2) against the live NotebookClient with
/// an in-memory SwiftData store:
///
///   • `updateBlockDrawing` round-trips ink bytes and mirrors the ink
///     thumbnail onto the page-card projection the library grid reads.
///   • `bindCanonicalCanvasWidth` binds exactly once per notebook.
///
/// (This file previously also covered legacy-payload migration; that
/// machinery was deleted 2026-07-22 per the no-migrations rule — the
/// legacy `NotePage` fields retired as a direct schema edit.)
final class InkBlockPersistenceTests: XCTestCase {

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

    // MARK: - Ink round-trip

    @MainActor
    func test_updateBlockDrawing_roundTripsInkBytes() async throws {
        let (client, ctx) = makeClient()
        let (_, page) = try seedNotebookPage(context: ctx)
        let block = try await client.insertBlock(page.id, .ink, nil)

        let inkBytes = Data("ink-payload".utf8)
        try await client.updateBlockDrawing(block.id, inkBytes, nil)

        let loaded = try await client.loadBlockDrawing(block.id)
        XCTAssertEqual(loaded, inkBytes)
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
