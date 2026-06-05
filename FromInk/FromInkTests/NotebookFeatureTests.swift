import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `NotebookFeature` — specifically the
/// per-page template persistence + inheritance contract:
///
/// 1. A template choice persists to **the current page** via
///    `NotebookClient.setPageTemplate`, not to a notebook-wide field.
/// 2. The refreshed snapshot lands in `state.pages` so the canvas
///    reads the new template without round-tripping through the
///    store-change observer.
/// 3. Creating a new page **inherits** the current page's template —
///    the user's recent choice flows forward.
/// 4. The store-change observation and Toolbar scope effects are
///    overridden / disabled where they would steal cooperative
///    cancellation away from the assertion path.
final class NotebookFeatureTests: XCTestCase {

    private let notebookID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
    private let page1ID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let page2ID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func snapshot(
        id: UUID,
        index: Int,
        templateName: String = CanvasTemplate.none.rawValue
    ) -> NotePageSnapshot {
        NotePageSnapshot(
            id: id,
            notebookID: notebookID,
            index: index,
            createdAt: now,
            modifiedAt: now,
            templateName: templateName,
            thumbnailData: nil,
            ocrTextExcerpt: nil,
            headerCount: 0,
            linkCount: 0
        )
    }

    private func makeState(pages: [NotePageSnapshot]) -> NotebookFeature.State {
        var s = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        s.pages = pages
        s.hasLoadedOnce = true
        return s
    }

    /// Stub that throws for every endpoint except the two the
    /// template flow touches. Built by full-construction rather than
    /// `var c = .testValue; c.field = ...` because partial property
    /// overrides on TCA dependency structs don't propagate reliably
    /// under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (the captured
    /// closures still reference the original .testValue's live
    /// closures and segfault when the reducer's effect calls them).
    /// Documented in CLAUDE.md.
    private func makeClient(
        setPageTemplate: @escaping @Sendable (UUID, String) async throws -> NotePageSnapshot,
        createPage: @escaping @Sendable (UUID, String) async throws -> NotePageSnapshot
            = { _, _ in throw CancellationError() }
    ) -> NotebookClient {
        NotebookClient(
            fetchAllNotebooks: { throw CancellationError() },
            fetchNotebook: { _ in throw CancellationError() },
            fetchPage: { _ in throw CancellationError() },
            fetchPagesForNotebook: { _ in throw CancellationError() },
            fetchAllFolders: { throw CancellationError() },
            fetchHistoryForPage: { _ in throw CancellationError() },
            fetchHistoryForNotebook: { _ in throw CancellationError() },
            fetchAllTags: { throw CancellationError() },
            createNotebook: { _, _, _ in throw CancellationError() },
            renameNotebook: { _, _ in throw CancellationError() },
            deleteNotebook: { _ in throw CancellationError() },
            touchNotebookModified: { _ in throw CancellationError() },
            fetchAllPDFs: { throw CancellationError() },
            fetchRecentPDFs: { _ in throw CancellationError() },
            fetchPDF: { _ in throw CancellationError() },
            fetchPDFData: { _ in throw CancellationError() },
            findPDFByContentHash: { _ in throw CancellationError() },
            importPDF: { _, _ in throw CancellationError() },
            touchPDFOpened: { _ in throw CancellationError() },
            createPage: createPage,
            deletePage: { _ in throw CancellationError() },
            reindexPages: { _, _ in throw CancellationError() },
            transferPage: { _, _, _ in throw CancellationError() },
            setPageTemplate: setPageTemplate,
            saveDrawing: { _, _, _ in throw CancellationError() },
            updateOCR: { _, _ in throw CancellationError() },
            updateTypedText: { _, _ in throw CancellationError() },
            addHeader: { _, _, _ in throw CancellationError() },
            updateHeaderOCR: { _, _ in throw CancellationError() },
            deleteHeader: { _ in throw CancellationError() },
            addLink: { _, _, _, _ in throw CancellationError() },
            updateLink: { _, _ in throw CancellationError() },
            deleteLink: { _ in throw CancellationError() },
            recordHistory: { _, _ in throw CancellationError() },
            updateHistoryStatus: { _, _ in throw CancellationError() },
            addRegion: { _, _, _, _ in throw CancellationError() },
            createFolder: { _, _ in throw CancellationError() },
            deleteFolder: { _ in throw CancellationError() },
            moveNotebookToFolder: { _, _ in throw CancellationError() },
            createTag: { _, _ in throw CancellationError() },
            addTagToNotebook: { _, _ in throw CancellationError() },
            removeTagFromNotebook: { _, _ in throw CancellationError() }
        )
    }

    // MARK: - Derived: currentTemplate reads the current page

    @MainActor
    func test_currentTemplate_readsCurrentPage() {
        var s = makeState(pages: [
            snapshot(id: page1ID, index: 0, templateName: CanvasTemplate.linesWide.rawValue),
            snapshot(id: page2ID, index: 1, templateName: CanvasTemplate.grid.rawValue),
        ])
        s.currentIndex = 0
        XCTAssertEqual(s.currentTemplate, .linesWide)

        s.currentIndex = 1
        XCTAssertEqual(s.currentTemplate, .grid)
    }

    @MainActor
    func test_currentTemplate_emptyPages_returnsNone() {
        let s = makeState(pages: [])
        XCTAssertEqual(s.currentTemplate, .none)
    }

    @MainActor
    func test_currentTemplate_legacyBlankString_decodesAsNone() {
        var s = makeState(pages: [snapshot(id: page1ID, index: 0, templateName: "blank")])
        s.currentIndex = 0
        // Legacy "blank" rows (from before the schema lined up with
        // CanvasTemplate.none.rawValue) must decode as .none so the
        // renderer always has something safe to draw.
        XCTAssertEqual(s.currentTemplate, .none)
    }

    // MARK: - templateSelected writes to the current page

    @MainActor
    func test_templateSelected_persistsToCurrentPage() async {
        let captured = LockIsolated<(UUID, String)?>(nil)
        let refreshed = snapshot(
            id: page1ID, index: 0,
            templateName: CanvasTemplate.linesWide.rawValue
        )
        let initial = makeState(pages: [snapshot(id: page1ID, index: 0)])

        let store = TestStore(initialState: initial) {
            NotebookFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                setPageTemplate: { pageID, name in
                    captured.setValue((pageID, name))
                    return refreshed
                }
            )
        }

        // No state mutation yet — the trigger fires the effect. The
        // toolbar panel close also runs here (panel was nil already).
        await store.send(.templateSelected(.linesWide))
        await store.receive(.pageTemplateUpdated(refreshed)) {
            $0.pages = [refreshed]
        }

        XCTAssertEqual(captured.value?.0, page1ID)
        XCTAssertEqual(captured.value?.1, CanvasTemplate.linesWide.rawValue)
    }

    @MainActor
    func test_templateSelected_emptyPages_isNoOp() async {
        let store = TestStore(initialState: makeState(pages: [])) {
            NotebookFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                setPageTemplate: { _, _ in
                    XCTFail("setPageTemplate must not be called when there is no current page")
                    return self.snapshot(id: self.page1ID, index: 0)
                }
            )
        }

        // No current page → no effect dispatched.
        await store.send(.templateSelected(.grid))
    }

    // MARK: - addPageTapped inherits the current template

    @MainActor
    func test_addPageTapped_inheritsCurrentPageTemplate() async {
        let inheritedRaw = CanvasTemplate.grid.rawValue
        let captured = LockIsolated<(UUID, String)?>(nil)
        let newSnap = snapshot(id: page2ID, index: 1, templateName: inheritedRaw)

        var initial = makeState(pages: [
            snapshot(id: page1ID, index: 0, templateName: inheritedRaw)
        ])
        initial.currentIndex = 0

        let store = TestStore(initialState: initial) {
            NotebookFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                setPageTemplate: { _, _ in
                    XCTFail("addPage path must not call setPageTemplate")
                    return self.snapshot(id: self.page1ID, index: 0)
                },
                createPage: { notebookID, templateName in
                    captured.setValue((notebookID, templateName))
                    return newSnap
                }
            )
        }

        await store.send(.addPageTapped)
        await store.receive(.pageCreated(newSnap)) {
            $0.pages.append(newSnap)
            $0.currentIndex = 1
        }

        XCTAssertEqual(captured.value?.0, notebookID)
        XCTAssertEqual(
            captured.value?.1, inheritedRaw,
            "New page must inherit the current page's template raw value"
        )
    }

    /// Full round-trip of the user's stated contract:
    /// Page A (linesWide) → select grid on A → add page → B inherits
    /// grid → select dots on B → add page → C inherits dots.
    @MainActor
    func test_inheritance_flowsForwardAcrossTemplateSwitches() async {
        let pageAID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let pageBID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let pageCID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

        let pageAGridSnap = snapshot(
            id: pageAID, index: 0,
            templateName: CanvasTemplate.grid.rawValue
        )
        let pageBSnap = snapshot(
            id: pageBID, index: 1,
            templateName: CanvasTemplate.grid.rawValue
        )
        let pageBDotsSnap = snapshot(
            id: pageBID, index: 1,
            templateName: CanvasTemplate.dots.rawValue
        )
        let pageCSnap = snapshot(
            id: pageCID, index: 2,
            templateName: CanvasTemplate.dots.rawValue
        )

        // setPageTemplate returns whichever matches the requested raw value.
        let setPageTemplateStub: @Sendable (UUID, String) async throws -> NotePageSnapshot
            = { pageID, raw in
                switch (pageID, raw) {
                case (pageAID, CanvasTemplate.grid.rawValue): return pageAGridSnap
                case (pageBID, CanvasTemplate.dots.rawValue): return pageBDotsSnap
                default:
                    XCTFail("unexpected setPageTemplate call: \(pageID) \(raw)")
                    return pageAGridSnap
                }
            }
        // createPage returns the next snapshot.
        let createPageStub: @Sendable (UUID, String) async throws -> NotePageSnapshot
            = { _, raw in
                switch raw {
                case CanvasTemplate.grid.rawValue: return pageBSnap
                case CanvasTemplate.dots.rawValue: return pageCSnap
                default:
                    XCTFail("unexpected createPage call with raw=\(raw)")
                    return pageBSnap
                }
            }

        var initial = makeState(pages: [snapshot(id: pageAID, index: 0)])
        initial.currentIndex = 0

        let store = TestStore(initialState: initial) {
            NotebookFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                setPageTemplate: setPageTemplateStub,
                createPage: createPageStub
            )
        }

        // 1. Select grid on page A.
        await store.send(.templateSelected(.grid))
        await store.receive(.pageTemplateUpdated(pageAGridSnap)) {
            $0.pages = [pageAGridSnap]
        }
        XCTAssertEqual(store.state.currentTemplate, .grid)

        // 2. Add page — B inherits grid.
        await store.send(.addPageTapped)
        await store.receive(.pageCreated(pageBSnap)) {
            $0.pages.append(pageBSnap)
            $0.currentIndex = 1
        }
        XCTAssertEqual(store.state.currentTemplate, .grid)

        // 3. Select dots on page B.
        await store.send(.templateSelected(.dots))
        await store.receive(.pageTemplateUpdated(pageBDotsSnap)) {
            $0.pages = [pageAGridSnap, pageBDotsSnap]
        }
        XCTAssertEqual(store.state.currentTemplate, .dots)

        // 4. Add page — C inherits dots.
        await store.send(.addPageTapped)
        await store.receive(.pageCreated(pageCSnap)) {
            $0.pages.append(pageCSnap)
            $0.currentIndex = 2
        }
        XCTAssertEqual(store.state.currentTemplate, .dots)
    }
}
