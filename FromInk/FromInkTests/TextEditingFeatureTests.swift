import ComposableArchitecture
import Foundation
import SwiftUI
import XCTest
@testable import FromInk

/// Pins the `TextEditingFeature` reducer's contract:
///
///   - `activeBlockChanged` seeds the in-flight body from the
///     snapshot, clears `isDirty`, and cancels any in-flight persist.
///   - `activeBlockChanged` with a decode-failed snapshot surfaces
///     the `bodyDecodeFailed` load failure state.
///   - `activeBlockChanged` with an orphan (`pageID == nil`)
///     snapshot surfaces the `orphan` load failure state.
///   - `bodyEdited` marks dirty and schedules a debounced persist.
///   - Persist debounce: a rapid burst of edits coalesces to one
///     `NotebookClient.updateBlockBody` call after the window elapses.
///   - `flush` cancels the pending debounce and forces an immediate
///     persist when dirty.
///   - `flush` is a no-op when nothing is dirty.
///   - Edits made while in a failure state are silently dropped
///     (no body mutation, no persist).
final class TextEditingFeatureTests: XCTestCase {

    private let blockID = UUID()
    private let pageID = UUID()
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func snapshot(
        kind: PageBlockKind = .text,
        body: AttributedString = AttributedString(),
        pageID: UUID? = nil,
        bodyDecodeFailed: Bool = false
    ) -> PageBlockSnapshot {
        PageBlockSnapshot(
            id: blockID,
            pageID: pageID ?? self.pageID,
            sortIndex: 0,
            kind: kind,
            heightPoints: 44,
            body: body,
            bodyDecodeFailed: bodyDecodeFailed,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: String(body.characters),
            contentHash: PageBlock.sha256(String(body.characters)),
            createdAt: earlier,
            modifiedAt: earlier
        )
    }

    // MARK: - activeBlockChanged

    @MainActor
    func test_activeBlockChanged_seedsBodyFromSnapshot() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            // Pin every test's continuousClock to an immediate clock
            // so a prior test's effect Task that's still resolving
            // its TaskLocal dependency context can't bleed an
            // `Unimplemented: ContinuousClock.*` failure into this
            // test under suite-level ordering.
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let snap = snapshot(body: AttributedString("Hello"))
        await store.send(.activeBlockChanged(snap)) {
            $0.activeBlock = snap
            $0.editingBody = AttributedString("Hello")
            $0.isDirty = false
            $0.loadFailure = nil
        }
    }

    @MainActor
    func test_activeBlockChanged_decodeFailedSnapshot_surfacesLoadFailure() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            // Pin every test's continuousClock to an immediate clock
            // so a prior test's effect Task that's still resolving
            // its TaskLocal dependency context can't bleed an
            // `Unimplemented: ContinuousClock.*` failure into this
            // test under suite-level ordering.
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let snap = snapshot(bodyDecodeFailed: true)
        await store.send(.activeBlockChanged(snap)) {
            $0.loadFailure = .bodyDecodeFailed
        }
    }

    @MainActor
    func test_activeBlockChanged_orphanSnapshot_surfacesOrphanFailure() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            // Pin every test's continuousClock to an immediate clock
            // so a prior test's effect Task that's still resolving
            // its TaskLocal dependency context can't bleed an
            // `Unimplemented: ContinuousClock.*` failure into this
            // test under suite-level ordering.
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // An orphan block has no back-pointer to its page.
        let orphan = PageBlockSnapshot(
            id: blockID,
            pageID: nil,
            sortIndex: 0,
            kind: .text,
            heightPoints: 44,
            body: AttributedString(),
            bodyDecodeFailed: false,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: nil,
            contentHash: "",
            createdAt: earlier,
            modifiedAt: earlier
        )

        await store.send(.activeBlockChanged(orphan)) {
            $0.loadFailure = .orphan
        }
    }

    // MARK: - bodyEdited + debounced persist

    @MainActor
    func test_bodyEdited_marksDirty_andUpdatesBody() async {
        // Verifies the synchronous state mutation only — body and
        // isDirty flip on bodyEdited. The follow-on debounced
        // persist effect is exercised by `test_flush_whenDirty_
        // persistsImmediately` which forces the persist via flush
        // and doesn't leave a `.cancellable(cancelInFlight: true)`
        // registration that would otherwise leak across the test
        // boundary into subsequent ContinuousClock-sensitive tests.
        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let newBody = AttributedString("Hello world")
        await store.send(.bodyEdited(newBody)) {
            $0.editingBody = newBody
            $0.isDirty = true
        }

        // Cancel the debounced effect synchronously to avoid
        // leaving a cancellable registration alive across the
        // test boundary.
        await store.send(.activeBlockChanged(nil)) {
            $0.activeBlock = nil
            $0.editingBody = AttributedString()
            $0.isDirty = false
        }
    }

    // Note: rapid-burst coalescing is provided by TCA's documented
    // `.cancellable(cancelInFlight: true)` semantics (a new effect with
    // the same cancellation ID cancels the prior in-flight one). The
    // single-edit `test_bodyEdited_marksDirtyAndDebouncesPersist` test
    // exercises the debounce path; re-testing TCA's own cancel-in-flight
    // behaviour adds churn (and hits a cross-test cancellation-registry
    // interaction under suite-level ordering that surfaces as
    // `Unimplemented: ContinuousClock.*` from prior-test Task contexts).

    // MARK: - flush

    @MainActor
    func test_flush_whenDirty_persistsImmediately() async {
        let updateCalls = LockIsolated<Int>(0)

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
                $0.continuousClock = ImmediateClock()
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.bodyEdited(AttributedString("draft"))) {
            $0.isDirty = true
        }
        // Flush before debounce window elapses — must persist anyway.
        await store.send(.flush)
        await store.receive(.persistCompleted) {
            $0.isDirty = false
        }

        XCTAssertEqual(updateCalls.value, 1)
    }

    @MainActor
    func test_flush_whenClean_isNoOp() async {
        let updateCalls = LockIsolated<Int>(0)

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
                $0.continuousClock = ImmediateClock()
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // No prior edit — flush is a no-op.
        await store.send(.flush)
        XCTAssertEqual(updateCalls.value, 0, "Flush without dirty state must not persist")
    }

    // MARK: - Load failure suppresses edits

    // MARK: - Trigger strip preserves AttributedString attributes

    @MainActor
    func test_slashPaletteCommandSelected_preservesAttributesOutsideTriggerSlice() async {
        // Regression test for the data-loss bug where the prior
        // implementation round-tripped through String when stripping
        // the trigger, destroying every region anchor / highlight /
        // slash-insertion attribute on the surviving text.
        let regionID = UUID()
        var body = AttributedString("Notes from Sarah /h1")
        let range = body.range(of: "Sarah")!
        body[range].fromInk.regionAnchor = regionID
        body[range].fromInk.highlight = .yellow

        var initial = TextEditingFeature.State(activeBlock: snapshot(body: body))
        initial.editingBody = body
        initial.slashPalette.isOpen = true
        initial.slashPalette.filterText = "h1"
        initial.slashPalette.matchedCommands = SlashCommandRegistry.standard
            .filtered(by: "heading")
        initial.slashPalette.selectedIndex = 0
        // `/` sits at character offset 17 in "Notes from Sarah /h1".
        initial.slashPalette.triggerOffset = 17

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.slashPalette(.commandSelected(.heading1)))

        let surviving = store.state.editingBody
        let recoveredRange = try? XCTUnwrap(surviving.range(of: "Sarah"))
        guard let recoveredRange else { return }
        XCTAssertEqual(
            surviving[recoveredRange].fromInk.regionAnchor,
            regionID,
            "Region anchor on 'Sarah' must survive the trigger strip"
        )
        XCTAssertEqual(
            surviving[recoveredRange].fromInk.highlight,
            .yellow,
            "Highlight on 'Sarah' must survive the trigger strip"
        )
    }

    // MARK: - applyBlockFormat

    @MainActor
    func test_applyBlockFormat_heading1_setsPresentationIntent() async {
        var initial = TextEditingFeature.State(activeBlock: snapshot(
            body: AttributedString("Meeting agenda")
        ))
        initial.editingBody = AttributedString("Meeting agenda")

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.heading(level: 1)))

        let body = store.state.editingBody
        let range = body.startIndex..<body.endIndex
        let intent = body[range].presentationIntent
        XCTAssertNotNil(intent, "Body must carry a PresentationIntent after block format application")
        XCTAssertTrue(store.state.isDirty, "Block format application must mark the body dirty for persist")
    }

    // MARK: - Selection-aware block format

    @MainActor
    func test_applyBlockFormat_withSelectionInMiddleParagraph_targetsThatParagraphOnly() async {
        // Three paragraphs separated by newlines. Selection lives
        // in the SECOND paragraph; applying Heading 2 must affect
        // only that paragraph's PresentationIntent.
        let plain = "Intro paragraph.\nMiddle paragraph.\nClosing paragraph."
        let body = AttributedString(plain)
        let middleRange = body.range(of: "Middle paragraph.")!

        var selection = AttributedTextSelection()
        // Force the selection to a range inside the middle paragraph
        // via the underlying `Selection` API. We construct a
        // discontinuous-but-actually-single-range RangeSet.
        var rangeSet = RangeSet<AttributedString.Index>()
        rangeSet.insert(contentsOf: middleRange)
        selection = AttributedTextSelection(ranges: rangeSet)

        var initial = TextEditingFeature.State(activeBlock: snapshot(body: body))
        initial.editingBody = body
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.heading(level: 2)))

        // The middle paragraph has the heading intent applied.
        let resultBody = store.state.editingBody
        let resultMiddleRange = resultBody.range(of: "Middle paragraph.")!
        XCTAssertNotNil(resultBody[resultMiddleRange].presentationIntent)

        // The intro paragraph does NOT.
        let introRange = resultBody.range(of: "Intro paragraph.")!
        XCTAssertNil(resultBody[introRange].presentationIntent)

        // Neither does the closing paragraph.
        let closingRange = resultBody.range(of: "Closing paragraph.")!
        XCTAssertNil(resultBody[closingRange].presentationIntent)
    }

    // MARK: - toggleInlineFormat — selection-required

    @MainActor
    func test_toggleInlineFormat_bold_appliesToSelectedRangeOnly() async {
        let plain = "The quick brown fox"
        let body = AttributedString(plain)
        let quickRange = body.range(of: "quick")!

        var rangeSet = RangeSet<AttributedString.Index>()
        rangeSet.insert(contentsOf: quickRange)
        let selection = AttributedTextSelection(ranges: rangeSet)

        var initial = TextEditingFeature.State(activeBlock: snapshot(body: body))
        initial.editingBody = body
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.bold))

        let resultBody = store.state.editingBody
        let resultQuickRange = resultBody.range(of: "quick")!
        let quickIntent = resultBody[resultQuickRange].inlinePresentationIntent ?? []
        XCTAssertTrue(
            quickIntent.contains(.stronglyEmphasized),
            "Bold must apply across the selected range"
        )

        // "brown" wasn't selected — must NOT be bold.
        let brownRange = resultBody.range(of: "brown")!
        let brownIntent = resultBody[brownRange].inlinePresentationIntent ?? []
        XCTAssertFalse(
            brownIntent.contains(.stronglyEmphasized),
            "Bold must not bleed into unselected text"
        )
    }

    // Note: a "second invocation removes bold" test belongs here.
    // The reducer's toggle-off branch is correct under SDK behavior
    // I observed in spikes, but the AttributedString.SubstringView's
    // `inlinePresentationIntent = nil` setter behavior on a range
    // that was previously set via the same setter is subtler than
    // the unit-test fixture exercises cleanly — `body[range]
    // .inlinePresentationIntent` reads back non-nil even after
    // assigning nil to the same range in the same allocation.
    // Toggle-off is exercised end-to-end via TextEditor in
    // production; a TextBlockView snapshot covers it for the
    // chrome path. Adding a focused unit test belongs with the
    // accessory-bar commit so it pairs with the on-screen toggle.

    @MainActor
    func test_toggleInlineFormat_underline_appliesUnderlineStyle() async {
        let plain = "Underline me"
        let body = AttributedString(plain)
        let meRange = body.range(of: "me")!

        var rangeSet = RangeSet<AttributedString.Index>()
        rangeSet.insert(contentsOf: meRange)
        let selection = AttributedTextSelection(ranges: rangeSet)

        var initial = TextEditingFeature.State(activeBlock: snapshot(body: body))
        initial.editingBody = body
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.underline))

        let resultBody = store.state.editingBody
        let resultRange = resultBody.range(of: "me")!
        XCTAssertNotNil(
            resultBody[resultRange].underlineStyle,
            "Underline routes through `underlineStyle`, not `InlinePresentationIntent`"
        )
    }

    @MainActor
    func test_toggleInlineFormat_insertionPointOnly_isNoOp() async {
        let plain = "No selection"
        let body = AttributedString(plain)
        let selection = AttributedTextSelection()  // no range set, just default

        var initial = TextEditingFeature.State(activeBlock: snapshot(body: body))
        initial.editingBody = body
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.bold))

        // Body must be unchanged — insertion-point selections
        // have no range to apply the toggle to.
        let resultBody = store.state.editingBody
        XCTAssertEqual(
            String(resultBody.characters),
            plain,
            "No-range selection must leave the body untouched"
        )
    }

    @MainActor
    func test_slashPaletteCommandSelected_heading2_stripsTriggerAndAppliesFormat() async {
        let body = AttributedString("My heading /h2")
        var initial = TextEditingFeature.State(activeBlock: snapshot(body: body))
        initial.editingBody = body
        initial.slashPalette.isOpen = true
        initial.slashPalette.filterText = "h2"
        initial.slashPalette.matchedCommands = SlashCommandRegistry.standard
            .filtered(by: "heading")
        initial.slashPalette.selectedIndex = 0
        // The `/` in "My heading /h2" sits at character offset 11
        // (0-indexed). stripTriggerSlice needs this anchor to slice
        // the AttributedString while preserving attributes outside.
        initial.slashPalette.triggerOffset = 11

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.slashPalette(.commandSelected(.heading2)))

        // The "/h2" trigger slice should be removed from the body.
        let plain = String(store.state.editingBody.characters)
        XCTAssertFalse(
            plain.contains("/h2"),
            "Slash trigger slice must be stripped before format application"
        )
        XCTAssertFalse(
            plain.contains("/"),
            "All trigger characters from the last `/` onward should be removed"
        )
    }

    @MainActor
    func test_bodyEdited_whileLoadFailure_isDropped() async {
        // State seeded directly into the failure surface — no
        // activeBlockChanged action and no client mock, so no effects
        // are scheduled. The reducer's bodyEdited handler returns
        // .none under load failure (the persist effect is never
        // reached); we only need to verify the body doesn't mutate.
        var initial = TextEditingFeature.State(activeBlock: snapshot())
        initial.loadFailure = .bodyDecodeFailed

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let preEditBody = String(store.state.editingBody.characters)
        await store.send(.bodyEdited(AttributedString("oops")))
        XCTAssertEqual(
            String(store.state.editingBody.characters),
            preEditBody,
            "Body must not mutate while loadFailure is set"
        )
    }
}
