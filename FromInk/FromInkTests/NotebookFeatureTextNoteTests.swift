import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// TestStore coverage for the textNote branch of `NotebookFeature`.
///
/// **Scope.** This file focuses on the synchronous reducer mutations
/// that determine variant routing and the no-op behaviour on the ink
/// path. The effect-driven dispatch (loadTextBlocks → textBlocksLoaded
/// → activeBlockChanged, including the auto-seed path when blocks are
/// empty) is fully exercised by the round-trip integration test in
/// `TextBlockIntegrationTests`, which uses the live NotebookClient
/// against an in-memory SwiftData store. That test catches the same
/// regressions without TaskLocal dependency-context pollution that
/// surfaces when multiple effect-scheduling tests are paired here
/// under suite-level ordering.
///
/// Pins:
///   • `notebookTypeResolved(.textNote)` flips the routing field that
///     `NotebookScreen` switches on to present `TextNoteWiringView`.
///   • `notebookTypeResolved(.notebook)` does NOT trigger block
///     loading — the ink path stays on its existing canvas surface.
final class NotebookFeatureTextNoteTests: XCTestCase {

    private let notebookID = UUID()
    private let pageID = UUID()
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func pageSnapshot() -> NotePageSnapshot {
        NotePageSnapshot(
            id: pageID,
            notebookID: notebookID,
            index: 0,
            createdAt: now,
            modifiedAt: now,
            templateName: CanvasTemplate.none.rawValue,
            thumbnailData: nil,
            ocrTextExcerpt: nil,
            headerCount: 0,
            linkCount: 0
        )
    }

    // MARK: - Ink variants don't load blocks

    @MainActor
    func test_notebookTypeResolved_inkVariant_doesNotLoadBlocks() async {
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

        XCTAssertEqual(loadCalls.value, 0, "Ink variants must NOT trigger block loading")
    }

    @MainActor
    func test_notebookTypeResolved_quickSheetVariant_doesNotLoadBlocks() async {
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

        XCTAssertEqual(loadCalls.value, 0)
    }

    // MARK: - textNote variant resolves type
    //
    // The synchronous part (state.notebookType flips to .textNote) is
    // verified here. The effect chain (loadTextBlocks → textBlocksLoaded
    // → activeBlockChanged with seed when empty) is covered by
    // `TextBlockIntegrationTests.test_textNote_pageOpenSeedsTextBlock`
    // which exercises the same dispatch through the live NotebookClient.

    @MainActor
    func test_notebookTypeResolved_textNote_flipsRoutingState() async {
        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            // Returning empty here means the textBlocksLoaded handler
            // will attempt a seed via insertBlock; we provide a stub
            // so the effect chain doesn't crash, but the synchronous
            // state.notebookType mutation is what this test asserts.
            $0.notebookClient.fetchBlocksForPage = { _ in [] }
            $0.notebookClient.insertBlock = { _, _, _ in
                throw CancellationError()
            }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.notebookTypeResolved(.textNote)) {
            $0.notebookType = .textNote
        }
    }
}
