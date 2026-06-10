import ComposableArchitecture
import Foundation
import SwiftData
import XCTest
@testable import FromInk

/// End-to-end integration coverage for the text-block persistence path:
///
///     RichTextDocument (block tree with marks)
///     ↓ PageBlockSnapshot.encodeBody (JSON, sorted keys)
///     ↓ NotebookClient.updateBlockBody → SwiftData write
///     ↓ NotebookClient.fetchBlocksForPage → snapshot projection
///     ↓ PageBlockSnapshot.decodeBody (JSON decode)
///     → RichTextDocument with structure preserved
///
/// The unit tests cover each leg in isolation; this test catches the
/// encoding-side regressions they miss (the NotebookClient.live write
/// path, the snapshot projection, the page-level aggregate refresh).
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

    // MARK: - Plain document round-trip

    @MainActor
    func test_writeAndReadBlockBody_singleParagraph_preservesContent() async throws {
        let (client, ctx) = makeClient()
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let original = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "Meeting notes:\nQ3 budget review on Friday.")
            ]))
        ])
        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, original.plainText)

        let blocks = try await client.fetchBlocksForPage(pageID)
        let textBlock = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        XCTAssertEqual(textBlock.plainText, "Meeting notes:\nQ3 budget review on Friday.")
        let recovered = try XCTUnwrap(textBlock.document)
        XCTAssertEqual(recovered, original)
    }

    // MARK: - Multi-block round-trip with marks

    @MainActor
    func test_writeAndReadBlockBody_headingPlusParagraphWithBold_preservesStructure() async throws {
        let (client, ctx) = makeClient()
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let original = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Title")])),
            Block(kind: .paragraph(inline: [
                Inline(text: "Plain "),
                Inline(text: "bold", marks: [.bold]),
                Inline(text: " and "),
                Inline(text: "italic", marks: [.italic])
            ]))
        ])
        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, original.plainText)

        let blocks = try await client.fetchBlocksForPage(pageID)
        let textBlock = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        let recovered = try XCTUnwrap(textBlock.document)
        XCTAssertEqual(
            recovered, original,
            "Block structure + inline marks must survive the full encode → SwiftData write → fetch → decode pipeline"
        )
    }

    // MARK: - Highlight round-trip

    @MainActor
    func test_writeAndReadBlockBody_preservesHighlightMark() async throws {
        let (client, ctx) = makeClient()
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let original = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "This is "),
                Inline(text: "important", marks: [.highlight(.yellow)]),
                Inline(text: " context.")
            ]))
        ])
        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, original.plainText)

        let blocks = try await client.fetchBlocksForPage(pageID)
        let textBlock = try XCTUnwrap(blocks.first(where: { $0.kind == .text }))
        let recovered = try XCTUnwrap(textBlock.document)
        guard case .paragraph(let inline) = recovered.blocks.first?.kind else {
            XCTFail("Expected paragraph")
            return
        }
        XCTAssertEqual(inline[1].marks, [.highlight(.yellow)])
    }

    // MARK: - contentHash + page-level aggregate

    @MainActor
    func test_updateBlockBody_refreshesPageExtractedAggregates() async throws {
        let (client, ctx) = makeClient()
        let (notebookID, pageID) = try seedNotebookPage(context: ctx)

        let block = try await client.insertBlock(pageID, .text, nil)

        let original = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Sample paragraph.")]))
        ])
        let data = try PageBlockSnapshot.encodeBody(original)
        try await client.updateBlockBody(block.id, data, original.plainText)

        let modelCtx = ctx.context()
        let page = try XCTUnwrap(
            try modelCtx.fetch(
                FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == pageID })
            ).first
        )
        XCTAssertEqual(page.extractedText, "Sample paragraph.")
        XCTAssertNotNil(page.extractedTextHash)
        XCTAssertFalse(page.extractedTextHash?.isEmpty ?? true)

        XCTAssertEqual(page.modifiedAt, now)
        _ = notebookID
    }
}
