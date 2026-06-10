import SwiftData
import XCTest
@testable import FromInk

/// Schema + snapshot contract tests for `PageBlock` and
/// `PageBlockSnapshot`.
///
/// Pins:
///   - In-memory insert + fetch round-trip preserves every field.
///   - CloudKit-safe defaults (all fields optional / defaulted).
///   - Plain back-pointer on `PageBlock.page` (no `@Relationship`
///     macro on the child side — parent-side macro lives on
///     `NotePage.blocks`).
///   - `kind` is read-only post-construction.
///   - `PageBlock.sha256` produces a stable 64-character lowercase
///     hex digest.
///   - `PageBlockSnapshot.init(model:loadDrawingData:)` projects the
///     right fields per kind, and reports `pageID == nil` for orphans
///     (no fabricated UUID).
///   - `PageBlockSnapshot.decodeBody` reports `bodyDecodeFailed = true`
///     on garbage input rather than silently returning an empty body.
///
/// Container is in-memory; CloudKit isn't exercised — these tests
/// validate the SwiftData shape that CloudKit will eventually sync.
final class PageBlockTests: XCTestCase {

    // MARK: - Container

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PageBlock.self, NotePage.self, Notebook.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - Round-trip

    @MainActor
    func test_insertAndFetch_preservesEveryField() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let blockID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_780_000_000)
        let block = PageBlock(
            id: blockID,
            page: page,
            sortIndex: 3,
            kind: .ink,
            heightPoints: 240,
            createdAt: createdAt
        )
        block.drawingData = Data([0x01, 0x02, 0x03])
        block.thumbnailData = Data([0xFF, 0xFE])
        block.ocrText = "meeting notes"
        block.contentHash = PageBlock.sha256("meeting notes")
        ctx.insert(block)
        try ctx.save()

        let fetched = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<PageBlock>()).first
        )
        XCTAssertEqual(fetched.id, blockID)
        XCTAssertEqual(fetched.sortIndex, 3)
        XCTAssertEqual(fetched.kind, .ink)
        XCTAssertEqual(fetched.heightPoints, 240)
        XCTAssertEqual(fetched.createdAt, createdAt)
        XCTAssertEqual(fetched.modifiedAt, createdAt)
        XCTAssertEqual(fetched.drawingData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(fetched.thumbnailData, Data([0xFF, 0xFE]))
        XCTAssertEqual(fetched.ocrText, "meeting notes")
        XCTAssertEqual(fetched.page?.id, page.id)
        // Bidirectional relationship populated from the parent side.
        XCTAssertEqual(page.blocks?.first?.id, blockID)
    }

    // MARK: - CloudKit-safe defaults

    @MainActor
    func test_defaultsAreCloudKitSafe() throws {
        let ctx = try makeContext()
        let block = PageBlock()
        ctx.insert(block)
        try ctx.save()

        let fetched = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<PageBlock>()).first
        )
        // All payload fields default to nil — no required scalars
        // that CloudKit could trip on.
        XCTAssertNil(fetched.bodyData)
        XCTAssertNil(fetched.plainText)
        XCTAssertNil(fetched.drawingData)
        XCTAssertNil(fetched.thumbnailData)
        XCTAssertNil(fetched.ocrText)
        XCTAssertNil(fetched.audioData)
        XCTAssertNil(fetched.transcript)
        XCTAssertEqual(fetched.contentHash, "")
        XCTAssertEqual(fetched.sortIndex, 0)
        XCTAssertEqual(fetched.kind, .text)
        XCTAssertEqual(fetched.heightPoints, PageBlock.defaultHeightPoints)
    }

    // MARK: - Kind immutability

    @MainActor
    func test_kind_isReadOnly_postConstruction() {
        let block = PageBlock(kind: .text)
        XCTAssertEqual(block.kind, .text)
        // No setter — direct mutation through kindRaw must be the
        // only path (used by the model layer; reducers never reach
        // for it).
        block.kindRaw = PageBlockKind.ink.rawValue
        XCTAssertEqual(block.kind, .ink)
    }

    // MARK: - Empty-state heights

    @MainActor
    func test_emptyHeightPoints_perKind() {
        XCTAssertEqual(PageBlock.emptyHeightPoints(for: .text), 44)
        XCTAssertEqual(PageBlock.emptyHeightPoints(for: .ink), 200)
        XCTAssertEqual(PageBlock.emptyHeightPoints(for: .voice), 88)
    }

    // MARK: - SHA256

    func test_sha256_emptyString_producesKnownDigest() {
        // SHA256("") is a well-known constant. Pinning it catches
        // accidental hashing of the wrong bytes (e.g. UTF-16 vs UTF-8).
        XCTAssertEqual(
            PageBlock.sha256(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func test_sha256_isStable_acrossCalls() {
        let input = "Some meeting notes — Q3 budget"
        XCTAssertEqual(PageBlock.sha256(input), PageBlock.sha256(input))
    }

    func test_sha256_outputShape_is64LowercaseHexChars() {
        let digest = PageBlock.sha256("payload")
        XCTAssertEqual(digest.count, 64)
        XCTAssertTrue(digest.allSatisfy { ($0.isHexDigit) && !$0.isUppercase })
    }

    // MARK: - Snapshot projection per kind

    @MainActor
    func test_snapshot_textBlock_projectsDocumentAndPlainText() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let block = PageBlock(page: page, sortIndex: 0, kind: .text)
        block.plainText = "Hello world"
        // Archive a real RichTextDocument so decodeBody exercises the
        // JSON path end-to-end.
        let original = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        block.bodyData = try PageBlockSnapshot.encodeBody(original)
        ctx.insert(block)
        try ctx.save()

        let snap = PageBlockSnapshot(model: block)
        XCTAssertEqual(snap.id, block.id)
        XCTAssertEqual(snap.pageID, page.id)
        XCTAssertEqual(snap.kind, .text)
        XCTAssertEqual(snap.plainText, "Hello world")
        XCTAssertNotNil(snap.document)
        XCTAssertEqual(snap.document?.plainText, "Hello world")
        XCTAssertFalse(snap.bodyDecodeFailed)
        XCTAssertNil(snap.drawingData)
        XCTAssertNil(snap.voice)
    }

    @MainActor
    func test_snapshot_inkBlock_loadDrawingDataFalse_dropsDrawingData() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let block = PageBlock(page: page, sortIndex: 0, kind: .ink)
        block.drawingData = Data([0x99, 0xAA])
        block.ocrText = "title"
        ctx.insert(block)
        try ctx.save()

        let lazy = PageBlockSnapshot(model: block, loadDrawingData: false)
        XCTAssertNil(lazy.drawingData, "Off-viewport snapshot should not carry the drawing payload")
        XCTAssertEqual(lazy.ocrText, "title", "ocrText is independent of drawing-data lazy load")

        let live = PageBlockSnapshot(model: block, loadDrawingData: true)
        XCTAssertEqual(live.drawingData, Data([0x99, 0xAA]))
    }

    @MainActor
    func test_snapshot_voiceBlock_projectsTranscriptAndAudioData() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let block = PageBlock(page: page, sortIndex: 0, kind: .voice)
        block.audioData = Data([0x10, 0x20, 0x30])
        block.transcript = "follow up on Q3 budget"
        block.transcriptConfidence = 0.92
        block.audioDurationSeconds = 32
        block.transcriptLanguage = "en-US"
        ctx.insert(block)
        try ctx.save()

        let snap = PageBlockSnapshot(model: block)
        let voice = try XCTUnwrap(snap.voice)
        XCTAssertEqual(voice.audioData, Data([0x10, 0x20, 0x30]))
        XCTAssertEqual(voice.transcript, "follow up on Q3 budget")
        XCTAssertEqual(voice.transcriptConfidence, 0.92)
        XCTAssertEqual(voice.durationSeconds, 32)
        XCTAssertEqual(voice.language, "en-US")
        XCTAssertNil(snap.document)
        XCTAssertNil(snap.drawingData)
    }

    @MainActor
    func test_snapshot_orphanBlock_reportsNilPageID() {
        // Block constructed without a parent — represents a persistence
        // inconsistency (e.g. a back-pointer dropped by SwiftData
        // cascade). The snapshot must NOT fabricate a UUID.
        let orphan = PageBlock(page: nil)
        let snap = PageBlockSnapshot(model: orphan)
        XCTAssertNil(snap.pageID, "Orphan blocks must report nil pageID rather than fabricating a UUID")
    }

    // MARK: - Body decode failure

    @MainActor
    func test_decodeBody_emptyData_returnsEmptyDocument_notFailed() {
        let result = PageBlockSnapshot.decodeBody(nil, blockID: UUID())
        XCTAssertEqual(result.document, .empty)
        XCTAssertFalse(result.failed, "Empty/nil bodyData is a normal empty-block state, not a decode failure")

        let result2 = PageBlockSnapshot.decodeBody(Data(), blockID: UUID())
        XCTAssertEqual(result2.document, .empty)
        XCTAssertFalse(result2.failed)
    }

    @MainActor
    func test_decodeBody_garbageBytes_reportsFailedTrue() {
        // 16 bytes of nonsense — not a valid JSON document.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04,
                            0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C])
        let result = PageBlockSnapshot.decodeBody(garbage, blockID: UUID())
        XCTAssertTrue(result.failed, "Corrupted bodyData must surface as bodyDecodeFailed for the view layer to render a placeholder")
        XCTAssertEqual(result.document, .empty, "On failure the document is empty so the editor opens cleanly")
    }
}
