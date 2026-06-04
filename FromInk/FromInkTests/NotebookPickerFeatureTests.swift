import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `NotebookPickerFeature`. Asserts the phase
/// transitions, search filter behavior (via the resolved state, since
/// filter is a view-level concern), the three terminal page-selection
/// paths, the "More…" toggle, and the dismiss / back chrome.
///
/// The picker is delegate-only — every confirmation path emits a
/// `.delegate(.selected(...))` action. Tests assert both the action
/// payload (notebookID + page) and the absence of state mutation on the
/// delegate itself (delegate is parent-routing, not picker state).
///
@MainActor
final class NotebookPickerFeatureTests: XCTestCase {

    // MARK: - Fixtures

    private let notebookA = NotebookSnapshot(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        title: "Quarterly Planning",
        createdAt: Date(timeIntervalSince1970: 0),
        modifiedAt: Date(timeIntervalSince1970: 0),
        coverColorHex: "#FAFAF8",
        isPinned: false,
        isArchived: false,
        sortOrder: 0,
        notebookType: .notebook,
        folderID: nil,
        pageCount: 4,
        firstPageThumbnailData: nil,
        tagIDs: []
    )

    private let notebookB = NotebookSnapshot(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        title: "Recipes",
        createdAt: Date(timeIntervalSince1970: 0),
        modifiedAt: Date(timeIntervalSince1970: 0),
        coverColorHex: "#FAFAF8",
        isPinned: false,
        isArchived: false,
        sortOrder: 0,
        notebookType: .notebook,
        folderID: nil,
        pageCount: 2,
        firstPageThumbnailData: nil,
        tagIDs: []
    )

    private func makePage(id: UUID, notebookID: UUID, index: Int) -> NotePageSnapshot {
        NotePageSnapshot(
            id: id,
            notebookID: notebookID,
            index: index,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            templateName: "blank",
            thumbnailData: nil,
            ocrTextExcerpt: nil,
            headerCount: 0,
            linkCount: 0
        )
    }

    /// `NotebookClient` stub that returns the supplied notebooks and
    /// pages. Every other closure throws — the picker only calls
    /// `fetchAllNotebooks` and `fetchPagesForNotebook`, so a wider
    /// surface area would just be noise.
    private func makeClient(
        notebooks: [NotebookSnapshot] = [],
        pagesByNotebookID: [UUID: [NotePageSnapshot]] = [:]
    ) -> NotebookClient {
        var client = NotebookClient.throwing
        client.fetchAllNotebooks = { notebooks }
        client.fetchPagesForNotebook = { id in pagesByNotebookID[id] ?? [] }
        return client
    }

    // MARK: - Appeared / loading

    func test_appeared_loadsNotebooks_andClearsLoading() async {
        let loaded = [notebookA, notebookB]
        let store = TestStore(initialState: NotebookPickerFeature.State()) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient(notebooks: loaded)
        }

        await store.send(.appeared) {
            $0.isLoading = true
        }
        await store.receive(.notebooksLoaded(loaded)) {
            $0.notebooks = loaded
            $0.isLoading = false
        }
    }

    func test_appeared_clientThrows_falls_throughToEmpty() async {
        // The reducer treats a throw the same as a successful empty
        // fetch — the picker shows the empty state rather than
        // surfacing an error to the user (network/storage errors at
        // this layer are infrastructure-level, not picker-actionable).
        let store = TestStore(initialState: NotebookPickerFeature.State()) {
            NotebookPickerFeature()
        } withDependencies: {
            var client = NotebookClient.throwing
            client.fetchAllNotebooks = { throw CancellationError() }
            $0.notebookClient = client
        }

        await store.send(.appeared) { $0.isLoading = true }
        await store.receive(.notebooksLoaded([])) {
            $0.notebooks = []
            $0.isLoading = false
        }
    }

    // MARK: - Search

    func test_searchTextChanged_updatesState() async {
        let store = TestStore(initialState: NotebookPickerFeature.State()) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.searchTextChanged("recipes")) {
            $0.searchText = "recipes"
        }
    }

    // MARK: - Phase: notebook → page

    func test_notebookTapped_advancesToPageSelection_andLoadsPages() async {
        let page1 = makePage(id: UUID(), notebookID: notebookA.id, index: 0)
        let page2 = makePage(id: UUID(), notebookID: notebookA.id, index: 1)
        var state = NotebookPickerFeature.State()
        state.notebooks = [notebookA, notebookB]
        let store = TestStore(initialState: state) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient(
                notebooks: [notebookA, notebookB],
                pagesByNotebookID: [notebookA.id: [page2, page1]]   // out of order
            )
        }

        let tappedID = notebookA.id
        let tappedTitle = notebookA.title
        await store.send(.notebookTapped(tappedID)) {
            $0.phase = .pageSelection(
                notebookID: tappedID,
                notebookTitle: tappedTitle
            )
            $0.showsPageThumbnails = false
            $0.isLoading = true
        }
        await store.receive(.pagesLoaded([page2, page1])) {
            // Reducer sorts by index ascending — pages arrive
            // arbitrarily ordered from the client, picker normalizes
            // so the thumbnail grid renders left-to-right by page #.
            $0.pages = [page1, page2]
            $0.isLoading = false
        }
    }

    func test_notebookTapped_unknownID_isNoOp() async {
        // Programmatic guard: if a tap arrives for a notebook not in
        // state.notebooks the reducer ignores it. Can't happen via the
        // UI (the grid only renders loaded snapshots) but worth pinning
        // to prevent accidental phase corruption via .send.
        let store = TestStore(initialState: NotebookPickerFeature.State()) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.notebookTapped(UUID()))   // no state change
    }

    // MARK: - Phase: back

    func test_backTapped_returnsToNotebookSelection_andClearsPages() async {
        let page = makePage(id: UUID(), notebookID: notebookA.id, index: 0)
        var state = NotebookPickerFeature.State()
        state.phase = .pageSelection(notebookID: notebookA.id, notebookTitle: "X")
        state.pages = [page]
        state.showsPageThumbnails = true
        let store = TestStore(initialState: state) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.backTapped) {
            $0.phase = .notebookSelection
            $0.pages = []
            $0.showsPageThumbnails = false
        }
    }

    // MARK: - Page selection delegates

    func test_lastEditedPageTapped_emitsSelected_lastEdited() async {
        var state = NotebookPickerFeature.State()
        state.phase = .pageSelection(notebookID: notebookA.id, notebookTitle: "X")
        let store = TestStore(initialState: state) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.lastEditedPageTapped)
        await store.receive(.delegate(.selected(notebookID: notebookA.id, page: .lastEdited)))
    }

    func test_newPageTapped_emitsSelected_new() async {
        var state = NotebookPickerFeature.State()
        state.phase = .pageSelection(notebookID: notebookA.id, notebookTitle: "X")
        let store = TestStore(initialState: state) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.newPageTapped)
        await store.receive(.delegate(.selected(notebookID: notebookA.id, page: .new)))
    }

    func test_pageThumbnailTapped_emitsSelected_existing() async {
        let page = makePage(id: UUID(), notebookID: notebookA.id, index: 0)
        var state = NotebookPickerFeature.State()
        state.phase = .pageSelection(notebookID: notebookA.id, notebookTitle: "X")
        state.pages = [page]
        state.showsPageThumbnails = true
        let store = TestStore(initialState: state) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.pageThumbnailTapped(page.id))
        await store.receive(
            .delegate(.selected(notebookID: notebookA.id, page: .existing(pageID: page.id)))
        )
    }

    /// Defensive — page-selection-only actions sent while in
    /// `.notebookSelection` should be no-ops, not crashes. Guards
    /// against accidental phase mismatches from upstream.
    func test_pageActions_whileInNotebookSelection_areNoOps() async {
        let store = TestStore(initialState: NotebookPickerFeature.State()) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.lastEditedPageTapped)
        await store.send(.newPageTapped)
        await store.send(.pageThumbnailTapped(UUID()))
    }

    // MARK: - More toggle

    func test_morePagesTapped_togglesThumbnails() async {
        var state = NotebookPickerFeature.State()
        state.phase = .pageSelection(notebookID: notebookA.id, notebookTitle: "X")
        let store = TestStore(initialState: state) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.morePagesTapped) { $0.showsPageThumbnails = true }
        await store.send(.morePagesTapped) { $0.showsPageThumbnails = false }
    }

    // MARK: - Dismiss

    func test_dismissTapped_emitsDelegateDismissed() async {
        let store = TestStore(initialState: NotebookPickerFeature.State()) {
            NotebookPickerFeature()
        } withDependencies: {
            $0.notebookClient = makeClient()
        }

        await store.send(.dismissTapped)
        await store.receive(.delegate(.dismissed))
    }
}
