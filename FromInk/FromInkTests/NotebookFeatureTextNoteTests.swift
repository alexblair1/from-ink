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

    // MARK: - Seed in-flight guard (readiness audit A5)

    private func blockSnapshot(pageID: UUID?) -> PageBlockSnapshot {
        PageBlockSnapshot(
            id: UUID(),
            pageID: pageID,
            sortIndex: 0,
            kind: .text,
            heightPoints: 44,
            document: .empty,
            bodyDecodeFailed: false,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: "",
            contentHash: PageBlock.sha256(""),
            sourceVoiceBlockID: nil,
            createdAt: now,
            modifiedAt: now
        )
    }

    /// Two empty block loads racing the first seed insert must produce
    /// exactly ONE inserted block. Before the in-flight guard, each
    /// empty result dispatched its own `insertBlock` — duplicate text
    /// blocks on the page.
    @MainActor
    func test_textBlocksLoaded_emptyTwiceBeforeSeedLands_insertsOnce() async {
        let insertCalls = LockIsolated<Int>(0)
        let seeded = blockSnapshot(pageID: pageID)

        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true
        initial.notebookType = .textNote

        // The insert suspends on this clock so the SECOND load
        // genuinely races the in-flight seed. (A fast stub wouldn't
        // exercise the race: non-exhaustive TestStore processes the
        // queued `textBlockSeeded` before the next send, clearing the
        // flag and making the second load look legitimate.)
        let clock = TestClock()
        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.notebookClient.insertBlock = { _, _, _ in
                insertCalls.withValue { $0 += 1 }
                try await clock.sleep(for: .seconds(1))
                return seeded
            }
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.textBlocksLoaded([])) {
            $0.isSeedingTextBlock = true
        }
        // Second empty load lands while the seed insert is still
        // suspended — the guard must hold.
        await store.send(.textBlocksLoaded([]))

        await clock.advance(by: .seconds(1))
        await store.receive(.textBlockSeeded(seeded)) {
            $0.isSeedingTextBlock = false
        }
        await store.receive(.textEditing(.activeBlockChanged(seeded)))
        await store.finish()

        XCTAssertEqual(insertCalls.value, 1, "Racing empty loads must not double-seed")
    }

    /// A seed that lands after the user swiped to another page clears
    /// the in-flight flag but does NOT hand the editor a block from
    /// the page they left.
    @MainActor
    func test_textBlockSeeded_forStalePage_clearsFlagWithoutRouting() async {
        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true
        initial.notebookType = .textNote
        initial.isSeedingTextBlock = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // Seed targets a DIFFERENT page than the one on screen.
        let stale = blockSnapshot(pageID: UUID())
        await store.send(.textBlockSeeded(stale)) {
            $0.isSeedingTextBlock = false
        }
        await store.finish()
        XCTAssertNil(
            store.state.textEditing.activeBlock,
            "A stale-page seed must not become the active editor block"
        )
    }

    /// A failed seed (nil result) re-arms seeding so the empty-state
    /// tap can retry.
    @MainActor
    func test_textBlockSeeded_nil_reArmsSeeding() async {
        var initial = NotebookFeature.State(notebookID: notebookID, notebookTitle: "Test")
        initial.pages = [pageSnapshot()]
        initial.hasLoadedOnce = true
        initial.notebookType = .textNote
        initial.isSeedingTextBlock = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotebookFeature() }
        ) {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.textBlockSeeded(nil)) {
            $0.isSeedingTextBlock = false
        }
    }
}
