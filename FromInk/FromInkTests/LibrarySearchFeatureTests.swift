import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `LibrarySearchFeature` — the reusable search
/// state machine that backs the browse surface, the future
/// picker-with-search variant, and any quick-switcher. Tests pin:
///
/// - `.appeared` fires an empty-query search → populates results.
/// - `.queryChanged` debounces + cancels in flight (verified via
///   `TestClock` advancement).
/// - `.resultTapped` emits the right delegate.
/// - `.resultsLoaded` clears `isSearching` + sets `hasLoadedOnce`.
///
@MainActor
final class LibrarySearchFeatureTests: XCTestCase {

    // MARK: - Fixtures

    private func notebook(_ title: String) -> LibrarySearchResult {
        .notebook(NotebookSnapshot(
            id: UUID(),
            title: title,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
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

    // MARK: - appeared

    func test_appeared_setsIsSearching_thenLoadsResults() async {
        let canned = [notebook("Quarterly Planning"), notebook("Recipes")]
        let store = TestStore(initialState: LibrarySearchFeature.State()) {
            LibrarySearchFeature()
        } withDependencies: {
            $0.librarySearchService = LibrarySearchService(
                search: { _, _ in canned }
            )
            $0.continuousClock = TestClock()
        }

        await store.send(.appeared) { $0.isSearching = true }
        await store.receive(.resultsLoaded(canned)) {
            $0.results = canned
            $0.isSearching = false
            $0.hasLoadedOnce = true
        }
    }

    // MARK: - queryChanged + debounce

    func test_queryChanged_debouncesBeforeFiringSearch() async {
        let clock = TestClock()
        let hit = notebook("hit:a")
        let store = TestStore(initialState: LibrarySearchFeature.State()) {
            LibrarySearchFeature()
        } withDependencies: {
            $0.librarySearchService = LibrarySearchService(
                search: { _, _ in [hit] }
            )
            $0.continuousClock = clock
        }

        await store.send(.queryChanged("a")) {
            $0.query = "a"
            $0.isSearching = true
        }
        // No search yet — debounce hasn't elapsed.
        await clock.advance(by: .milliseconds(249))
        // Advance past the debounce threshold.
        await clock.advance(by: .milliseconds(1))

        await store.receive(\.resultsLoaded) { state in
            state.results = [hit]
            state.isSearching = false
            state.hasLoadedOnce = true
        }
    }

    func test_queryChanged_rapidBurst_collapsesToFinalQuery() async {
        let clock = TestClock()
        let captured = LockIsolated<[String]>([])
        let store = TestStore(initialState: LibrarySearchFeature.State()) {
            LibrarySearchFeature()
        } withDependencies: {
            $0.librarySearchService = LibrarySearchService(
                search: { query, _ in
                    captured.withValue { $0.append(query) }
                    return []
                }
            )
            $0.continuousClock = clock
        }

        await store.send(.queryChanged("a")) {
            $0.query = "a"
            $0.isSearching = true
        }
        await clock.advance(by: .milliseconds(100))
        await store.send(.queryChanged("ab")) {
            $0.query = "ab"
        }
        await clock.advance(by: .milliseconds(100))
        await store.send(.queryChanged("abc")) {
            $0.query = "abc"
        }
        // Only the final query survives past debounce.
        await clock.advance(by: .milliseconds(250))
        await store.receive(\.resultsLoaded) {
            $0.isSearching = false
            $0.hasLoadedOnce = true
        }

        XCTAssertEqual(captured.value, ["abc"])
    }

    // MARK: - resultTapped

    func test_resultTapped_known_emitsResultSelectedDelegate() async {
        let n = notebook("x")
        var seeded = LibrarySearchFeature.State()
        seeded.results = [n]

        let store = TestStore(initialState: seeded) {
            LibrarySearchFeature()
        } withDependencies: {
            $0.librarySearchService = .testValue
            $0.continuousClock = TestClock()
        }

        await store.send(.resultTapped(n.id))
        await store.receive(.delegate(.resultSelected(n)))
    }

    func test_resultTapped_unknownID_isNoOp() async {
        let store = TestStore(initialState: LibrarySearchFeature.State()) {
            LibrarySearchFeature()
        } withDependencies: {
            $0.librarySearchService = .testValue
            $0.continuousClock = TestClock()
        }

        await store.send(.resultTapped(UUID()))
    }
}
