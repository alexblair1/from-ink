import SwiftData
import XCTest
@testable import FromInk

/// Pins the persistence contract for `NoteRegion`:
///
/// - Insert + fetch roundtrip preserves every field.
/// - Defaults are CloudKit-safe (every property is optional or has a
///   default, no `@Attribute(.unique)`).
/// - Cascade-delete on the parent side (`NotePage → NoteRegion`)
///   removes the region when its page is deleted.
/// - Plain back-pointer on `NoteRegion.page` is NOT decorated with
///   `@Relationship` (would trigger SwiftData's duplicate-inverse
///   runtime error).
/// - `NoteRegionSnapshot` round-trips through the link-destination
///   union correctly for every case.
///
/// Container is in-memory; CloudKit isn't exercised — these tests
/// validate the SwiftData shape that CloudKit will eventually sync.
///
final class NoteRegionSchemaTests: XCTestCase {

    // MARK: - Container

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: NoteRegion.self, NotePage.self, Notebook.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - Roundtrip

    @MainActor
    func test_insertAndFetch_preservesEveryField() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let rect = CGRect(x: 12, y: 34, width: 56, height: 78)
        let regionID = UUID()
        let pdfID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_780_000_000)
        let region = NoteRegion(
            id: regionID,
            page: page,
            rect: rect,
            createdAt: createdAt,
            sortOrder: 3,
            isAnchored: false,
            headerOCRText: "Section A",
            linkExternalURL: "https://example.com/x",
            linkTargetPageID: nil,
            linkTargetNotebookID: nil,
            linkTargetPDFID: pdfID
        )
        ctx.insert(region)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<NoteRegion>()).first
        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.id, regionID)
        XCTAssertEqual(unwrapped.rect, rect)
        XCTAssertEqual(unwrapped.createdAt, createdAt)
        XCTAssertEqual(unwrapped.sortOrder, 3)
        XCTAssertEqual(unwrapped.isAnchored, false)
        XCTAssertEqual(unwrapped.headerOCRText, "Section A")
        XCTAssertEqual(unwrapped.linkExternalURL, "https://example.com/x")
        XCTAssertEqual(unwrapped.linkTargetPDFID, pdfID)
        XCTAssertEqual(unwrapped.page?.id, page.id)
    }

    // MARK: - CloudKit-safe defaults

    @MainActor
    func test_defaultsAreCloudKitSafe() throws {
        // A region inserted with the minimum required arguments must
        // populate every field with a sane default per the data
        // model EDD's CloudKit rules. No nil-only-after-init traps,
        // no `@Attribute(.unique)`.
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let region = NoteRegion(page: page, rect: .zero)
        ctx.insert(region)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<NoteRegion>()).first)
        XCTAssertEqual(fetched.rectX, 0)
        XCTAssertEqual(fetched.rectY, 0)
        XCTAssertEqual(fetched.rectWidth, 0)
        XCTAssertEqual(fetched.rectHeight, 0)
        XCTAssertTrue(fetched.isAnchored, "Default isAnchored should be true")
        XCTAssertNil(fetched.headerOCRText)
        XCTAssertNil(fetched.linkExternalURL)
        XCTAssertNil(fetched.linkTargetPageID)
        XCTAssertNil(fetched.linkTargetNotebookID)
        XCTAssertNil(fetched.linkTargetPDFID)
        XCTAssertEqual(fetched.sortOrder, 0)
    }

    // MARK: - Cascade

    @MainActor
    func test_deletingPage_cascadesToRegions() throws {
        // The cascade rule lives on `NotePage.regions`. Deleting a
        // page must remove its regions. The asymmetry (deleting a
        // region never deletes the page) is implicit — there's no
        // reverse cascade.
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)

        let r1 = NoteRegion(page: page, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let r2 = NoteRegion(page: page, rect: CGRect(x: 10, y: 10, width: 10, height: 10))
        ctx.insert(r1)
        ctx.insert(r2)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteRegion>()).count, 2)

        ctx.delete(page)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteRegion>()).count, 0)
    }

    @MainActor
    func test_deletingRegion_doesNotDeletePage() throws {
        let ctx = try makeContext()
        let page = NotePage()
        ctx.insert(page)
        let region = NoteRegion(page: page, rect: .zero)
        ctx.insert(region)
        try ctx.save()

        ctx.delete(region)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteRegion>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NotePage>()).count, 1)
    }

    // MARK: - Snapshot — link destination resolution

    func test_snapshot_externalURL_resolvesToExternal() throws {
        let region = NoteRegion(
            rect: .zero,
            linkExternalURL: "https://example.com/path"
        )
        let snap = NoteRegionSnapshot(model: region)
        switch snap.linkDestination {
        case .external(let url):
            XCTAssertEqual(url.absoluteString, "https://example.com/path")
        default:
            XCTFail("Expected .external, got \(snap.linkDestination)")
        }
    }

    func test_snapshot_whitespaceOnlyURL_collapsesToNone() throws {
        // Whitespace-only external URLs are trimmed away by the
        // snapshot init's `trimmingCharacters` pass and collapse to
        // `.none` — they never masquerade as `.external` via
        // `URL(string:)`'s lenient behavior. The `.broken` fallback
        // is reserved for non-empty inputs that fail strict URL
        // parsing; finding a reliable repro for that path on modern
        // iOS is hard (URL(string:) accepts almost anything), so we
        // pin the whitespace-trim contract here and leave the
        // genuine-broken case for a future test.
        let region = NoteRegion(rect: .zero, linkExternalURL: "   ")
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertEqual(snap.linkDestination, .none)
    }

    func test_snapshot_internalPageTarget_resolvesToPage() throws {
        let pageID = UUID()
        let region = NoteRegion(rect: .zero, linkTargetPageID: pageID)
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertEqual(snap.linkDestination, .page(pageID))
    }

    func test_snapshot_internalNotebookTarget_resolvesToNotebook() throws {
        let notebookID = UUID()
        let region = NoteRegion(rect: .zero, linkTargetNotebookID: notebookID)
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertEqual(snap.linkDestination, .notebook(notebookID))
    }

    func test_snapshot_pdfTarget_resolvesToPDF() throws {
        let pdfID = UUID()
        let region = NoteRegion(rect: .zero, linkTargetPDFID: pdfID)
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertEqual(snap.linkDestination, .pdf(pdfID))
    }

    func test_snapshot_noLink_resolvesToNone() throws {
        let region = NoteRegion(rect: .zero)
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertEqual(snap.linkDestination, .none)
    }

    // MARK: - Snapshot — header normalization

    func test_snapshot_emptyHeaderText_collapsesToNil() throws {
        // Empty stored strings are CloudKit-friendly but semantically
        // identical to "no header." Adapters should render no badge
        // for empty headers, so the snapshot collapses the value.
        let region = NoteRegion(rect: .zero, headerOCRText: "")
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertNil(snap.headerOCRText)
    }

    func test_snapshot_nonEmptyHeaderText_passesThrough() throws {
        let region = NoteRegion(rect: .zero, headerOCRText: "Quarterly Plan")
        let snap = NoteRegionSnapshot(model: region)
        XCTAssertEqual(snap.headerOCRText, "Quarterly Plan")
    }

    // MARK: - Snapshot — hasAnyAssociation

    func test_snapshot_hasAnyAssociation_falseWhenEmpty() throws {
        let snap = NoteRegionSnapshot(model: NoteRegion(rect: .zero))
        XCTAssertFalse(snap.hasAnyAssociation)
    }

    func test_snapshot_hasAnyAssociation_trueWithHeader() throws {
        let snap = NoteRegionSnapshot(
            model: NoteRegion(rect: .zero, headerOCRText: "x")
        )
        XCTAssertTrue(snap.hasAnyAssociation)
    }

    func test_snapshot_hasAnyAssociation_trueWithLink() throws {
        let snap = NoteRegionSnapshot(
            model: NoteRegion(rect: .zero, linkExternalURL: "https://example.com")
        )
        XCTAssertTrue(snap.hasAnyAssociation)
    }
}
