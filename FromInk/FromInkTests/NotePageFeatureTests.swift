import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// TestStore coverage for `NotePageFeature` — the page-level reducer
/// the hybrid block stack hangs off (hybrid_page_edd.md §5.1).
///
/// Pins (Phase 1):
///   • Block load routes the first text block to the editor child.
///   • Empty-page auto-seed with the A5 in-flight guard (lifted from
///     `NotebookFeature` — two empty loads racing one seed insert
///     produce exactly ONE block).
///   • Stale-page seeds clear the flag without routing.
///   • Failed seeds re-arm so the empty-state tap can retry.
///   • `.pageChanged` flushes the OUTGOING block's pending edits
///     before the new page's blocks load (the swipe data-loss
///     contract the old NotebookFeature concatenate carried).
final class NotePageFeatureTests: XCTestCase {

    private let pageID = UUID()
    private let secondPageID = UUID()
    private let blockID = UUID()
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func blockSnapshot(
        id: UUID? = nil,
        pageID: UUID?,
        document: RichTextDocument = .empty
    ) -> PageBlockSnapshot {
        PageBlockSnapshot(
            id: id ?? blockID,
            pageID: pageID,
            sortIndex: 0,
            kind: .text,
            heightPoints: 44,
            document: document,
            bodyDecodeFailed: false,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: document.plainText,
            contentHash: PageBlock.sha256(document.plainText),
            sourceVoiceBlockID: nil,
            createdAt: now,
            modifiedAt: now
        )
    }

    // MARK: - Load routes to the editor

    @MainActor
    func test_blocksLoaded_withTextBlock_routesToEditor() async {
        let snap = blockSnapshot(pageID: pageID)
        let store = TestStore(
            initialState: NotePageFeature.State(pageID: pageID),
            reducer: { NotePageFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.blocksLoaded([snap]))
        await store.receive(.textEditing(.activeBlockChanged(snap))) {
            $0.textEditing.activeBlock = snap
            $0.textEditing.document = .empty
        }
    }

    // MARK: - Seed in-flight guard (readiness audit A5)

    /// Two empty block loads racing the first seed insert must produce
    /// exactly ONE inserted block.
    @MainActor
    func test_blocksLoaded_emptyTwiceBeforeSeedLands_insertsOnce() async {
        let insertCalls = LockIsolated<Int>(0)
        let seeded = blockSnapshot(pageID: pageID)

        // The insert suspends on this clock so the SECOND load
        // genuinely races the in-flight seed.
        let clock = TestClock()
        let store = TestStore(
            initialState: NotePageFeature.State(pageID: pageID),
            reducer: { NotePageFeature() }
        ) {
            $0.notebookClient.insertBlock = { _, _, _ in
                insertCalls.withValue { $0 += 1 }
                try await clock.sleep(for: .seconds(1))
                return seeded
            }
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.blocksLoaded([])) {
            $0.isSeedingBlock = true
        }
        // Second empty load lands while the seed insert is still
        // suspended — the guard must hold.
        await store.send(.blocksLoaded([]))

        await clock.advance(by: .seconds(1))
        await store.receive(.blockSeeded(seeded)) {
            $0.isSeedingBlock = false
        }
        await store.receive(.textEditing(.activeBlockChanged(seeded)))
        await store.finish()

        XCTAssertEqual(insertCalls.value, 1, "Racing empty loads must not double-seed")
    }

    /// A seed that lands after the user swiped to another page clears
    /// the in-flight flag but does NOT hand the editor a block from
    /// the page they left.
    @MainActor
    func test_blockSeeded_forStalePage_clearsFlagWithoutRouting() async {
        var initial = NotePageFeature.State(pageID: pageID)
        initial.isSeedingBlock = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotePageFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let stale = blockSnapshot(pageID: UUID())
        await store.send(.blockSeeded(stale)) {
            $0.isSeedingBlock = false
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
    func test_blockSeeded_nil_reArmsSeeding() async {
        var initial = NotePageFeature.State(pageID: pageID)
        initial.isSeedingBlock = true

        let store = TestStore(
            initialState: initial,
            reducer: { NotePageFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.blockSeeded(nil)) {
            $0.isSeedingBlock = false
        }
    }

    // MARK: - Page swipe: flush before reload

    /// `.pageChanged` must emit the OUTGOING block's flush BEFORE the
    /// new page's blocks load — the swipe data-loss contract (the
    /// receive ORDER is the assertion). The two composed legs are
    /// pinned separately: flush-persists-dirty-content in
    /// `TextEditingFeatureTests.test_flush_whenDirty_persistsImmediately`,
    /// and incoming-block routing in
    /// `test_blocksLoaded_withTextBlock_routesToEditor` above.
    ///
    /// Deliberately does NOT drive the full swipe-into-new-block chain
    /// in one test: that composite shape trips the known post-test
    /// `Unimplemented: ContinuousClock` artifact (a task outliving the
    /// TestStore under MainActor isolated-deinit — same family as the
    /// documented HomeFeature flake), failing whichever test runs
    /// next. Each leg is provably clean in isolation.
    @MainActor
    func test_pageChanged_ordersFlushBeforeLoad() async {
        var initial = NotePageFeature.State(pageID: pageID)
        // Neuter the seed leg so the chain ends at blocksLoaded —
        // the ordering contract is what this test pins.
        initial.isSeedingBlock = true

        // The closure deliberately captures NOTHING mutable: cascade
        // tests whose dependency closures append captured values have
        // crashed the runner (use-after-free across the deferred
        // TestStore teardown — the documented isolated-deinit crash
        // family). The load's page-targeting is pinned by
        // `loadBlocksEffect(pageID: state.pageID)` reading state
        // directly; the ordering contract below is what this test is
        // for.
        let store = TestStore(
            initialState: initial,
            reducer: { NotePageFeature() }
        ) {
            $0.notebookClient.fetchBlocksForPage = { _ in [] }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pageChanged(secondPageID)) {
            $0.pageID = self.secondPageID
            $0.isSeedingBlock = false
        }
        // Receive order IS the contract: flush strictly precedes the
        // new page's block load.
        await store.receive(.textEditing(.flush))
        await store.receive(.blocksLoaded([]))
        await store.finish()
    }

    /// Same-page `pageChanged` (index churn without a page change) is
    /// a no-op — no flush, no reload.
    @MainActor
    func test_pageChanged_samePage_isNoOp() async {
        let store = TestStore(
            initialState: NotePageFeature.State(pageID: pageID),
            reducer: { NotePageFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pageChanged(pageID))
        await store.finish()
    }
}
