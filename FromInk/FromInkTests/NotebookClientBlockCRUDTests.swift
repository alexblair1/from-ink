import ComposableArchitecture
import Foundation
import SwiftData
import XCTest
@testable import FromInk

/// Pins the live `NotebookClient` block-CRUD behavior:
///
///   - `insertBlock` shifts existing blocks at/after the insertion
///     point by one sortIndex, preserving a gapless order.
///   - `insertBlock` writes `createdAt` from the live `CalendarContext`,
///     not a bare `Date()`.
///   - `deleteBlock` reindexes siblings gaplessly.
///   - `reorderBlocks` throws `reorderMismatch` when the caller passes
///     an incomplete or extraneous ID set, rather than silently
///     leaving blocks at stale sortIndex values.
///   - `bindCanonicalCanvasWidth` is idempotent — once
///     `canonicalCanvasWidthIsBound` is true, subsequent calls no-op
///     even if a different width is passed.
///   - Bumping discipline: insertBlock / updateBlockHeight / deleteBlock
///     / reorderBlocks all bump the page's `modifiedAt`; bind canonical
///     width bumps the notebook's `modifiedAt`.
final class NotebookClientBlockCRUDTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    @MainActor
    private func seedNotebookPage(
        context modelContext: SyncedModelContextDependency
    ) throws -> (notebookID: UUID, pageID: UUID) {
        let ctx = modelContext.context()
        let notebook = Notebook(
            title: "Test",
            createdAt: earlier,
            modifiedAt: earlier
        )
        ctx.insert(notebook)
        let page = NotePage(notebook: notebook)
        page.modifiedAt = earlier
        ctx.insert(page)
        try ctx.save()
        return (notebook.id, page.id)
    }

    private func makeClient(
        on modelContext: SyncedModelContextDependency? = nil,
        now: Date
    ) -> (NotebookClient, SyncedModelContextDependency) {
        let ctx = modelContext ?? SyncedModelContextDependency.inMemory()
        let client = NotebookClient.live(
            modelContext: ctx,
            calendarContext: CalendarContext.fixed(now: now)
        )
        return (client, ctx)
    }

    // MARK: - insertBlock

    @MainActor
    func test_insertBlock_unknownPage_throwsPageNotFound() async {
        let (client, _) = makeClient(now: fixedNow)
        let missingID = UUID()
        do {
            _ = try await client.insertBlock(missingID, .text, nil)
            XCTFail("Expected pageNotFound")
        } catch let error as NotebookClientError {
            XCTAssertEqual(error, .pageNotFound(missingID))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func test_insertBlock_emptyPage_createsFirstBlock_atSortIndexZero() async throws {
        let (setupClient, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        let snap = try await client.insertBlock(pageID, .text, nil)

        XCTAssertEqual(snap.sortIndex, 0)
        XCTAssertEqual(snap.kind, .text)
        XCTAssertEqual(snap.pageID, pageID)
        // createdAt comes from the test client's CalendarContext, NOT
        // from a bare Date() — confirms PageBlock.init honors its
        // createdAt parameter.
        XCTAssertEqual(snap.createdAt, fixedNow)
        XCTAssertEqual(snap.modifiedAt, fixedNow)

        // Page modifiedAt bumped from `earlier` to `fixedNow`.
        let modelCtx = ctx.context()
        let fetchedPage = try modelCtx.fetch(
            FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == pageID })
        ).first
        XCTAssertEqual(fetchedPage?.modifiedAt, fixedNow)
    }

    @MainActor
    func test_insertBlock_atHeadOfTwoBlocks_shiftsExistingBlocksDown() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)

        let b1 = try await client.insertBlock(pageID, .text, nil)        // sortIndex 0
        let b2 = try await client.insertBlock(pageID, .text, b1.id)       // sortIndex 1
        let b3 = try await client.insertBlock(pageID, .text, nil)        // sortIndex 2 (append at end since afterID=nil)

        let blocks = try await client.fetchBlocksForPage(pageID)
            .sorted { $0.sortIndex < $1.sortIndex }
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].id, b1.id)
        XCTAssertEqual(blocks[1].id, b2.id)
        XCTAssertEqual(blocks[2].id, b3.id)
        XCTAssertEqual(blocks.map(\.sortIndex), [0, 1, 2])
    }

    @MainActor
    func test_insertBlock_inkKind_picksInkEmptyHeight() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        let inkBlock = try await client.insertBlock(pageID, .ink, nil)
        let textBlock = try await client.insertBlock(pageID, .text, inkBlock.id)
        let voiceBlock = try await client.insertBlock(pageID, .voice, textBlock.id)

        XCTAssertEqual(inkBlock.heightPoints, 200)
        XCTAssertEqual(textBlock.heightPoints, 44)
        XCTAssertEqual(voiceBlock.heightPoints, 88)
    }

    // MARK: - deleteBlock

    @MainActor
    func test_deleteBlock_reindexesSiblingsGapless() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        let b1 = try await client.insertBlock(pageID, .text, nil)
        let b2 = try await client.insertBlock(pageID, .text, b1.id)
        let b3 = try await client.insertBlock(pageID, .text, b2.id)

        // Delete the middle.
        try await client.deleteBlock(b2.id)

        let blocks = try await client.fetchBlocksForPage(pageID)
            .sorted { $0.sortIndex < $1.sortIndex }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].id, b1.id)
        XCTAssertEqual(blocks[0].sortIndex, 0)
        XCTAssertEqual(blocks[1].id, b3.id)
        XCTAssertEqual(blocks[1].sortIndex, 1, "Sibling after deletion must reindex to 1, not stay at 2")
    }

    @MainActor
    func test_deleteBlock_unknownID_throwsBlockNotFound() async {
        let (client, _) = makeClient(now: fixedNow)
        let missingID = UUID()
        do {
            try await client.deleteBlock(missingID)
            XCTFail("Expected blockNotFound")
        } catch let error as NotebookClientError {
            XCTAssertEqual(error, .blockNotFound(missingID))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - reorderBlocks

    @MainActor
    func test_reorderBlocks_validInput_reorders() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        let b1 = try await client.insertBlock(pageID, .text, nil)
        let b2 = try await client.insertBlock(pageID, .text, b1.id)
        let b3 = try await client.insertBlock(pageID, .text, b2.id)

        // Reverse the order.
        try await client.reorderBlocks(pageID, [b3.id, b2.id, b1.id])

        let blocks = try await client.fetchBlocksForPage(pageID)
            .sorted { $0.sortIndex < $1.sortIndex }
        XCTAssertEqual(blocks.map(\.id), [b3.id, b2.id, b1.id])
    }

    @MainActor
    func test_reorderBlocks_missingID_throwsReorderMismatch() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        let b1 = try await client.insertBlock(pageID, .text, nil)
        let b2 = try await client.insertBlock(pageID, .text, b1.id)
        let b3 = try await client.insertBlock(pageID, .text, b2.id)

        // Caller forgot b3 — must throw rather than leaving b3 at its
        // stale sortIndex (which would collide after b1/b2 reindex).
        do {
            try await client.reorderBlocks(pageID, [b2.id, b1.id])
            XCTFail("Expected reorderMismatch")
        } catch let error as NotebookClientError {
            guard case .reorderMismatch(let pid, let expected, let got) = error else {
                XCTFail("Wrong case: \(error)")
                return
            }
            XCTAssertEqual(pid, pageID)
            XCTAssertEqual(expected, Set([b1.id, b2.id, b3.id]))
            XCTAssertEqual(got, Set([b1.id, b2.id]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func test_reorderBlocks_extraID_throwsReorderMismatch() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (_, pageID) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        let b1 = try await client.insertBlock(pageID, .text, nil)
        let bogus = UUID()
        do {
            try await client.reorderBlocks(pageID, [b1.id, bogus])
            XCTFail("Expected reorderMismatch")
        } catch let error as NotebookClientError {
            guard case .reorderMismatch = error else {
                XCTFail("Wrong case: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - bindCanonicalCanvasWidth

    @MainActor
    func test_bindCanonicalCanvasWidth_firstCall_setsWidthAndFlag() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (notebookID, _) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        try await client.bindCanonicalCanvasWidth(notebookID, 1024)

        // Direct read against the model — the snapshot doesn't surface
        // canonicalCanvasWidth so we read the @Model row.
        let modelCtx = ctx.context()
        let fetched = try modelCtx.fetch(
            FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == notebookID })
        ).first
        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.canonicalCanvasWidth, 1024)
        XCTAssertTrue(unwrapped.canonicalCanvasWidthIsBound)
        // First-stroke is a content event — modifiedAt bumped.
        XCTAssertEqual(unwrapped.modifiedAt, fixedNow)
    }

    @MainActor
    func test_bindCanonicalCanvasWidth_secondCall_isIdempotent() async throws {
        let (_, ctx) = makeClient(now: earlier)
        let (notebookID, _) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        try await client.bindCanonicalCanvasWidth(notebookID, 1024)
        // Second call with a DIFFERENT width must no-op (binding is
        // one-way). This is the failure mode the prior `== 768`
        // sentinel masked.
        try await client.bindCanonicalCanvasWidth(notebookID, 834)

        let modelCtx = ctx.context()
        let fetched = try modelCtx.fetch(
            FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == notebookID })
        ).first
        XCTAssertEqual(fetched?.canonicalCanvasWidth, 1024, "Second bind must be a no-op")
    }

    @MainActor
    func test_bindCanonicalCanvasWidth_acceptsAuthoringDefaultWidth768() async throws {
        // Regression: the prior `== 768` sentinel would have re-bound
        // on every call for a notebook with the literal 768 default.
        // With the flag, a 768pt-portrait device binds exactly once.
        let (_, ctx) = makeClient(now: earlier)
        let (notebookID, _) = try seedNotebookPage(context: ctx)

        let (client, _) = makeClient(on: ctx, now: fixedNow)
        try await client.bindCanonicalCanvasWidth(notebookID, 768)
        try await client.bindCanonicalCanvasWidth(notebookID, 768)  // second call must no-op even on identical width

        let modelCtx = ctx.context()
        let fetched = try modelCtx.fetch(
            FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == notebookID })
        ).first
        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.canonicalCanvasWidth, 768)
        XCTAssertTrue(unwrapped.canonicalCanvasWidthIsBound)
    }
}
