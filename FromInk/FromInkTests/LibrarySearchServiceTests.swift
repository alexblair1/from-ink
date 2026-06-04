import XCTest
@testable import FromInk

/// Tests for `LibrarySearchService.rankAndFilter` — the pure-function
/// ranker that backs the live service. Keeping the rank logic at file
/// scope lets us exercise the tier behavior without spinning up a
/// `NotebookClient`.
///
/// The live `search(query:scope:)` closure is exercised indirectly via
/// `LibrarySearchFeatureTests` (substitutes a stub service into the
/// reducer's dependency).
///
final class LibrarySearchServiceTests: XCTestCase {

    // MARK: - Fixtures

    private func notebook(
        _ title: String,
        modified: Date = Date(timeIntervalSince1970: 0)
    ) -> LibrarySearchResult {
        .notebook(NotebookSnapshot(
            id: UUID(),
            title: title,
            createdAt: modified,
            modifiedAt: modified,
            coverColorHex: "#FAFAF8",
            isPinned: false,
            isArchived: false,
            sortOrder: 0,
            notebookType: .notebook,
            folderID: nil,
            pageCount: 1,
            firstPageThumbnailData: nil,
            tagIDs: []
        ))
    }

    private func folder(_ name: String) -> LibrarySearchResult {
        .folder(FolderSnapshot(
            id: UUID(),
            name: name,
            createdAt: Date(timeIntervalSince1970: 0),
            sortOrder: 0,
            parentID: nil,
            notebookCount: 0
        ))
    }

    // MARK: - Substring matching

    func test_rankAndFilter_filtersByCaseInsensitiveSubstring() {
        let items = [
            notebook("Quarterly Planning"),
            notebook("Personal journal"),
            notebook("Recipes")
        ]
        let result = LibrarySearchService.rankAndFilter(items, query: "PER")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Personal journal")
    }

    func test_rankAndFilter_emptyMatch_returnsEmpty() {
        let items = [notebook("a"), notebook("b")]
        XCTAssertEqual(
            LibrarySearchService.rankAndFilter(items, query: "zzz").count,
            0
        )
    }

    // MARK: - Two-tier ranking

    func test_rankAndFilter_prefixHits_rankAboveSubstringHits() {
        // Both "Calendar planning" and "Annual calendar review" contain
        // "cal", but only the first STARTS WITH it. The prefix hit
        // should come first regardless of modification date.
        let prefixHit = notebook("Calendar planning")
        let substringHit = notebook("Annual calendar review")
        let result = LibrarySearchService.rankAndFilter(
            [substringHit, prefixHit], query: "cal"
        )
        XCTAssertEqual(result.first?.title, "Calendar planning")
        XCTAssertEqual(result.last?.title, "Annual calendar review")
    }

    func test_rankAndFilter_withinTier_sortsByMostRecentFirst() {
        let older = notebook("Calendar 2024", modified: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = notebook("Calendar 2026", modified: Date(timeIntervalSince1970: 1_770_000_000))
        let result = LibrarySearchService.rankAndFilter(
            [older, newer], query: "cal"
        )
        XCTAssertEqual(result.first?.title, "Calendar 2026")
        XCTAssertEqual(result.last?.title, "Calendar 2024")
    }

    // MARK: - Mixed kinds

    func test_rankAndFilter_mixedKinds_rankIndependentOfKind() {
        // A folder named "calendar-archive" should rank by the same
        // tier logic as notebooks — kind is incidental to the rank.
        let folderResult = folder("Calendar archive")
        let nbResult = notebook("Calendar planning")
        let result = LibrarySearchService.rankAndFilter(
            [folderResult, nbResult], query: "cal"
        )
        // Both are prefix hits — within tier, ranking falls back to
        // rankingDate; both fixtures used `.distantPast` / fixed dates,
        // so the assertion is just that both appear.
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.title.lowercased().hasPrefix("cal") })
    }
}
