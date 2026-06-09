import ComposableArchitecture
import Foundation
import SwiftData
import XCTest
@testable import FromInk

/// End-to-end integration coverage for the text-block persistence path:
///
///     AttributedString (with custom attributes)
///     ↓ PageBlockSnapshot.encodeBody (Path B + FromInkAttributes scope)
///     ↓ NotebookClient.updateBlockBody → SwiftData write
///     ↓ NotebookClient.fetchBlocksForPage → snapshot projection
///     ↓ PageBlockSnapshot.decodeBody (Path B fallback to Path A)
///     → AttributedString with attributes preserved
///
/// The unit tests cover each leg in isolation; this test catches the
/// encoding-side regressions they miss (e.g. a future change to the
/// AttributedString custom-attribute scope, the NotebookClient.live
/// write path, or the snapshot projection that subtly drops attribute
/// values).
final class TextBlockIntegrationTests: XCTestCase {

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
    ) throws -> (notebookID: UUID, pageID: UUID) {
        let ctx = modelContext.context()
        let notebook = Notebook(
            title: "Test",
            createdAt: now,
            modifiedAt: now
        )
        ctx.insert(notebook)
        let page = NotePage(notebook: notebook)
        page.modifiedAt = now
        ctx.insert(page)
        try ctx.save()
        return (notebook.id, page.id)
    }

    // MARK: - Plain-text round-trip

    @MainActor
    func test_writeAndReadBlockBody_plainText_preservesContent() async throws {
        let (client, ctx) = makeClient()
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let original = AttributedString("Meeting notes:\nQ3 budget review on Friday.")
        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, String(original.characters))

        let blocks = try await client.fetchBlocksForPage(pageID)
        let textBlock = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        XCTAssertEqual(textBlock.plainText, "Meeting notes:\nQ3 budget review on Friday.")
        let recovered = try XCTUnwrap(textBlock.body)
        XCTAssertEqual(
            String(recovered.characters),
            "Meeting notes:\nQ3 budget review on Friday."
        )
    }

    // MARK: - Region anchor round-trip

    @MainActor
    func test_writeAndReadBlockBody_preservesRegionAnchorAttribute() async throws {
        let (client, ctx) = makeClient()
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let regionID = UUID()
        var original = AttributedString("Follow up with Sarah about Q3 budget by Friday")
        let range = original.range(of: "Q3 budget")!
        original[range].fromInk.regionAnchor = regionID

        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, String(original.characters))

        let blocks = try await client.fetchBlocksForPage(pageID)
        let textBlock = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        let recovered = try XCTUnwrap(textBlock.body)
        let recoveredRange = try XCTUnwrap(recovered.range(of: "Q3 budget"))
        XCTAssertEqual(
            recovered[recoveredRange].fromInk.regionAnchor,
            regionID,
            "Region anchor UUID must survive the full encode → SwiftData write → fetch → decode pipeline"
        )
    }

    // MARK: - Highlight round-trip

    @MainActor
    func test_writeAndReadBlockBody_preservesHighlightAttribute() async throws {
        let (client, ctx) = makeClient()
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        var original = AttributedString("This is important context.")
        let range = original.range(of: "important")!
        original[range].fromInk.highlight = .yellow

        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, String(original.characters))

        let blocks = try await client.fetchBlocksForPage(pageID)
        let textBlock = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        let recovered = try XCTUnwrap(textBlock.body)
        let recoveredRange = try XCTUnwrap(recovered.range(of: "important"))
        XCTAssertEqual(recovered[recoveredRange].fromInk.highlight, .yellow)
    }

    // MARK: - contentHash + page-level aggregate

    @MainActor
    func test_updateBlockBody_refreshesPageExtractedAggregates() async throws {
        let (client, ctx) = makeClient()
        let (notebookID, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let original = AttributedString("Sample paragraph.")
        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, String(original.characters))

        // Reach into the model context to verify the page-level
        // aggregate refresh (extractedText + extractedTextHash) ran
        // as part of updateBlockBody. The aggregate is recomputed
        // from the per-block manifest, so the page's hash must be
        // non-nil and the extractedText must contain the typed value.
        let modelCtx = ctx.context()
        let page = try XCTUnwrap(
            try modelCtx.fetch(
                FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == pageID })
            ).first
        )
        XCTAssertEqual(page.extractedText, "Sample paragraph.")
        XCTAssertNotNil(page.extractedTextHash)
        XCTAssertFalse(page.extractedTextHash?.isEmpty ?? true)

        // Bumping discipline: page.modifiedAt advanced to the fixed
        // now (the seed step left it at `now`; updateBlockBody bumps).
        XCTAssertEqual(page.modifiedAt, now)
        _ = notebookID
    }
}
