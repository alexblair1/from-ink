import SwiftData
import XCTest
@testable import FromInk

/// Pins the contract for `NotePage.recomputeExtractedAggregates`:
///
///   - Payloads joined in `sortIndex` order, regardless of insertion order.
///   - `\n\n` separator between blocks (so adjacent text blocks read
///     as separate paragraphs to Foundation Models / VoiceOver / search).
///   - Blocks with nil payload (e.g. an unstranscribed voice memo) are
///     dropped from the extracted text.
///   - Hash is composed from the per-block `contentHash` manifest
///     joined by `|`, hex-encoded SHA256.
///   - Reordering blocks changes the hash even when no content edits
///     occurred (so ML output keyed to the prior order refreshes).
///   - Mixed kinds compose without crashing.
final class NotePageAggregateTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PageBlock.self, NotePage.self, Notebook.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - Sort-order

    @MainActor
    func test_recompute_joinsInSortIndexOrder_notInsertionOrder() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        // Insert in REVERSE sort order to verify the recompute method
        // sorts before joining (rather than reading the relationship
        // array's iteration order).
        let third = PageBlock(page: page, sortIndex: 2, kind: .text)
        third.plainText = "third"
        third.contentHash = PageBlock.sha256("third")
        ctx.insert(third)

        let first = PageBlock(page: page, sortIndex: 0, kind: .text)
        first.plainText = "first"
        first.contentHash = PageBlock.sha256("first")
        ctx.insert(first)

        let second = PageBlock(page: page, sortIndex: 1, kind: .text)
        second.plainText = "second"
        second.contentHash = PageBlock.sha256("second")
        ctx.insert(second)

        try ctx.save()
        page.recomputeExtractedAggregates()

        XCTAssertEqual(page.extractedText, "first\n\nsecond\n\nthird")
    }

    // MARK: - Mixed kinds

    @MainActor
    func test_recompute_mixesTextInkVoice_inSortOrder() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let textBlock = PageBlock(page: page, sortIndex: 0, kind: .text)
        textBlock.plainText = "Meeting notes:"
        ctx.insert(textBlock)

        let inkBlock = PageBlock(page: page, sortIndex: 1, kind: .ink)
        inkBlock.ocrText = "sketch of org chart"
        ctx.insert(inkBlock)

        let voiceBlock = PageBlock(page: page, sortIndex: 2, kind: .voice)
        voiceBlock.transcript = "follow up tomorrow"
        ctx.insert(voiceBlock)

        try ctx.save()
        page.recomputeExtractedAggregates()

        XCTAssertEqual(
            page.extractedText,
            "Meeting notes:\n\nsketch of org chart\n\nfollow up tomorrow"
        )
    }

    // MARK: - Nil payloads dropped

    @MainActor
    func test_recompute_dropsBlocksWithNilPayloads() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        // A voice block with no transcript (capture failed, or still
        // transcribing) must NOT appear in extractedText as an empty
        // line.
        let textBlock = PageBlock(page: page, sortIndex: 0, kind: .text)
        textBlock.plainText = "before"
        ctx.insert(textBlock)

        let untranscribed = PageBlock(page: page, sortIndex: 1, kind: .voice)
        untranscribed.transcript = nil
        ctx.insert(untranscribed)

        let textAfter = PageBlock(page: page, sortIndex: 2, kind: .text)
        textAfter.plainText = "after"
        ctx.insert(textAfter)

        try ctx.save()
        page.recomputeExtractedAggregates()

        XCTAssertEqual(page.extractedText, "before\n\nafter")
    }

    // MARK: - Hash stability + reorder

    @MainActor
    func test_recompute_hash_changesWhenBlockOrderChanges() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let alpha = PageBlock(page: page, sortIndex: 0, kind: .text)
        alpha.plainText = "alpha"
        alpha.contentHash = PageBlock.sha256("alpha")
        ctx.insert(alpha)

        let beta = PageBlock(page: page, sortIndex: 1, kind: .text)
        beta.plainText = "beta"
        beta.contentHash = PageBlock.sha256("beta")
        ctx.insert(beta)

        try ctx.save()
        page.recomputeExtractedAggregates()
        let originalHash = page.extractedTextHash

        // Swap their sortIndex — same content, new order.
        alpha.sortIndex = 1
        beta.sortIndex = 0
        page.recomputeExtractedAggregates()

        XCTAssertNotEqual(
            page.extractedTextHash,
            originalHash,
            "Reordering blocks must trip the hash so ML output keyed to prior order can refresh"
        )
    }

    @MainActor
    func test_recompute_hash_isStableWhenContentIsUnchanged() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let alpha = PageBlock(page: page, sortIndex: 0, kind: .text)
        alpha.plainText = "alpha"
        alpha.contentHash = PageBlock.sha256("alpha")
        ctx.insert(alpha)
        try ctx.save()

        page.recomputeExtractedAggregates()
        let first = page.extractedTextHash
        page.recomputeExtractedAggregates()
        let second = page.extractedTextHash

        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
    }

    // MARK: - Empty page

    @MainActor
    func test_recompute_emptyPage_producesEmptyExtractedText() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)
        try ctx.save()

        page.recomputeExtractedAggregates()
        XCTAssertEqual(page.extractedText, "")
        // SHA256 of empty manifest is the known constant for "".
        XCTAssertEqual(
            page.extractedTextHash,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }
}
