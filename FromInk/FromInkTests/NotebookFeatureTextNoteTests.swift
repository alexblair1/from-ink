import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// TestStore coverage for the textNote branch of `NotebookFeature`
/// after the Phase 1 hybrid cutover (hybrid_page_edd.md §5.1):
/// the notebook no longer owns text-block loading — it attaches a
/// `NotePageFeature` child and forwards page swipes.
///
/// Pins:
///   • `notebookTypeResolved(.textNote)` creates the `notePage` child
///     for the current page and kicks its block load.
///   • Ink variants never create the child or touch block loading.
///   • Page swipes route through `.notePage(.pageChanged)` — the
///     flush-before-reload contract lives in `NotePageFeatureTests`.
///   • A store-change refresh keeps the EXISTING child (live editor
///     state survives) rather than recreating it.
final class NotebookFeatureTextNoteTests: XCTestCase {

    private let notebookID = UUID()
    private let pageID = UUID()
    private let secondPageID = UUID()
    private let now = Date(timeIntervalSince1970: 1_780_000_000)


    private func pageSnapshot(id: UUID? = nil, index: Int = 0) -> NotePageSnapshot {
        NotePageSnapshot(
            id: id ?? pageID,
            notebookID: notebookID,
            index: index,
            createdAt: now,
            modifiedAt: now,
            templateName: CanvasTemplate.none.rawValue,
            thumbnailData: nil,
            ocrTextExcerpt: nil,
            headerCount: 0,
            linkCount: 0
        )
    }

    // MARK: - Ink variants don't attach the page feature

    @MainActor
    func test_notebookTypeResolved_inkVariant_doesNotAttachNotePage() async {
        let loadCalls = LockIsolated<Int>(0)

        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.notebookClient.fetchBlocksForPage = { _ in
                loadCalls.withValue { $0 += 1 }
                return []
            }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.notebookTypeResolved(.notebook)) {
            $0.notebookType = .notebook
        }

        XCTAssertNil(store.state.notePage, "Ink variants must not attach the page feature")
        XCTAssertEqual(loadCalls.value, 0, "Ink variants must NOT trigger block loading")
    }

    @MainActor
    func test_notebookTypeResolved_quickSheetVariant_doesNotAttachNotePage() async {
        let loadCalls = LockIsolated<Int>(0)

        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.notebookClient.fetchBlocksForPage = { _ in
                loadCalls.withValue { $0 += 1 }
                return []
            }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.notebookTypeResolved(.quickSheet)) {
            $0.notebookType = .quickSheet
        }

        XCTAssertNil(store.state.notePage)
        XCTAssertEqual(loadCalls.value, 0)
    }

    // MARK: - textNote variant attaches the page feature

    @MainActor
    func test_notebookTypeResolved_textNote_attachesNotePageAndLoads() async {
        let loadCalls = LockIsolated<Int>(0)

        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true

        // Return an EXISTING block: the empty-page auto-seed leg is
        // pinned in NotePageFeatureTests, and ending the chain at the
        // seed avoids the known post-test ContinuousClock artifact
        // (see NotePageFeatureTests.test_pageChanged_ordersFlushBeforeLoad).
        let existing = PageBlockSnapshot(
            id: UUID(), pageID: pageID, sortIndex: 0, kind: .text,
            heightPoints: 44, document: .empty, bodyDecodeFailed: false,
            drawingData: nil, voice: nil, ocrText: nil, plainText: "",
            contentHash: PageBlock.sha256(""), sourceVoiceBlockID: nil,
            createdAt: now, modifiedAt: now
        )
        // The closure captures only the Int counter — cascade tests
        // whose dependency closures append captured values have
        // crashed the runner (use-after-free across the deferred
        // TestStore teardown; documented isolated-deinit crash
        // family).
        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.notebookClient.fetchBlocksForPage = { _ in
                loadCalls.withValue { $0 += 1 }
                return [existing]
            }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.notebookTypeResolved(.textNote)) {
            $0.notebookType = .textNote
            $0.notePage = NotePageFeature.State(pageID: self.pageID)
        }
        await store.receive(.notePage(.textEditing(.activeBlockChanged(existing)))) {
            $0.notePage?.textEditing.activeBlock = existing
        }
        await store.finish()

        XCTAssertEqual(loadCalls.value, 1, "Attaching the child kicks exactly one block load")
    }

    /// A store-change refresh (pagesLoaded with the child already
    /// attached, same page) must keep the EXISTING child — recreating
    /// it would reset live editor state mid-session.
    @MainActor
    func test_pagesLoaded_existingChildSamePage_reloadsWithoutRecreating() async {
        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true
        initial.notebookType = .textNote
        var child = NotePageFeature.State(pageID: pageID)
        child.isSeedingBlock = true  // marker: recreation would reset this
        initial.notePage = child

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.notebookClient.fetchBlocksForPage = { _ in [] }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pagesLoaded([pageSnapshot()]))
        await store.finish()

        XCTAssertEqual(
            store.state.notePage?.isSeedingBlock, true,
            "The existing child (and its in-flight state) must survive a refresh"
        )
    }

    // MARK: - Page swipe routes through the child

    @MainActor
    func test_currentIndexChanged_textNote_forwardsPageChangedToChild() async {
        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot(), pageSnapshot(id: secondPageID, index: 1)]
        initial.hasLoadedOnce = true
        initial.notebookType = .textNote
        var child = NotePageFeature.State(pageID: pageID)
        // Neuter the child's seed leg — the forwarding contract is
        // what this test pins; the seed path is pinned in
        // NotePageFeatureTests (and ending the chain early avoids the
        // known post-test ContinuousClock artifact).
        child.isSeedingBlock = true
        initial.notePage = child

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.notebookClient.fetchBlocksForPage = { _ in [] }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.currentIndexChanged(1)) {
            $0.currentIndex = 1
        }
        await store.receive(.notePage(.pageChanged(secondPageID))) {
            $0.notePage?.pageID = self.secondPageID
            $0.notePage?.isSeedingBlock = false
        }
        await store.finish()
    }
}
