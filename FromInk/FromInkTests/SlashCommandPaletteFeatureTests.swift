import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// Reducer-level coverage for the slash command palette:
///
///   • `openRequested` clears filter, resets selection, populates the
///     matched list from the registry dependency, stores the
///     `triggerOffset` so the editor can compute filter slices
///     without re-scanning the body.
///   • `filterChanged` recomputes `matchedCommands` and resets
///     `selectedIndex` to 0 (Apple Notes pattern — discoverable top-
///     of-results highlight).
///   • `keyboardNavigationKey` moves `selectedIndex` within bounds;
///     enter dispatches `commandSelected` for the current highlight;
///     escape dismisses.
///   • `commandSelected` closes the palette + clears triggerOffset
///     (so consecutive commands don't queue against stale state).
///   • `dismissed` clears all transient state.
final class SlashCommandPaletteFeatureTests: XCTestCase {

    // MARK: - openRequested

    @MainActor
    func test_openRequested_seedsMatchedListAndStoresTriggerOffset() async {
        let store = TestStore(
            initialState: SlashCommandPaletteFeature.State(),
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let leafID = UUID()
        await store.send(.openRequested(triggerOffset: 12, triggerBlockPath: [leafID])) {
            $0.isOpen = true
            $0.triggerOffset = 12
            $0.triggerBlockPath = [leafID]
            $0.filterText = ""
            $0.matchedCommands = SlashCommandRegistry.standard.descriptors
            $0.selectedIndex = 0
        }
    }

    // MARK: - filterChanged narrows + resets selection

    @MainActor
    func test_filterChanged_narrowsMatchedList() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.triggerOffset = 0
        initial.matchedCommands = SlashCommandRegistry.standard.descriptors

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.filterChanged("head"))

        let titles = store.state.matchedCommands.map(\.title)
        XCTAssertTrue(
            titles.allSatisfy { $0.localizedStandardContains("head") },
            "All matched commands must contain the filter substring"
        )
        XCTAssertFalse(store.state.matchedCommands.isEmpty)
    }

    @MainActor
    func test_filterChanged_emptyFilter_returnsFullList() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.filterText = "previousQuery"
        initial.matchedCommands = []

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.filterChanged(""))

        XCTAssertEqual(
            store.state.matchedCommands.count,
            SlashCommandRegistry.standard.descriptors.count
        )
    }

    @MainActor
    func test_filterChanged_resetsSelectedIndexToTopOfResults() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard.descriptors
        // Cursor was deep in the prior list.
        initial.selectedIndex = initial.matchedCommands.count - 1

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.filterChanged("heading"))

        XCTAssertEqual(
            store.state.selectedIndex,
            0,
            "Filter change must reset highlight to the top of filtered results"
        )
    }

    // MARK: - keyboard navigation

    @MainActor
    func test_keyboardNavigation_arrowDown_advancesSelection() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard.descriptors
        initial.selectedIndex = 0

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.keyboardNavigationKey(.down)) {
            $0.selectedIndex = 1
        }
        await store.send(.keyboardNavigationKey(.down)) {
            $0.selectedIndex = 2
        }
    }

    @MainActor
    func test_keyboardNavigation_arrowUp_decreasesSelection_clamped() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard.descriptors
        initial.selectedIndex = 1

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.keyboardNavigationKey(.up)) {
            $0.selectedIndex = 0
        }
        // Already at 0 — second up is a no-op.
        await store.send(.keyboardNavigationKey(.up))
        XCTAssertEqual(store.state.selectedIndex, 0)
    }

    @MainActor
    func test_keyboardNavigation_arrowDown_stopsAtListEnd() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard.descriptors
        let lastIndex = initial.matchedCommands.count - 1
        initial.selectedIndex = lastIndex

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.keyboardNavigationKey(.down))
        XCTAssertEqual(store.state.selectedIndex, lastIndex)
    }

    @MainActor
    func test_keyboardNavigation_enter_dispatchesCommandSelectedForHighlight() async {
        // Position selection on heading2 by id rather than index so
        // the test survives a registry reorder.
        let registry = SlashCommandRegistry.standard
        guard let heading2Index = registry.descriptors.firstIndex(where: { $0.id == .heading2 })
        else {
            XCTFail("Standard registry must contain heading2 for this test")
            return
        }

        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = registry.descriptors
        initial.selectedIndex = heading2Index

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.keyboardNavigationKey(.enter))
        await store.receive(.commandSelected(.heading2)) {
            $0.isOpen = false
            $0.selectedIndex = 0
            $0.filterText = ""
            $0.triggerOffset = nil
        }
    }

    @MainActor
    func test_keyboardNavigation_escape_dispatchesDismissed() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard.descriptors

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.keyboardNavigationKey(.escape))
        await store.receive(.dismissed) {
            $0.isOpen = false
        }
    }

    // MARK: - dismiss state cleanup

    @MainActor
    func test_dismissed_clearsTransientState() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.filterText = "head"
        initial.matchedCommands = SlashCommandRegistry.standard.filtered(by: "head")
        initial.selectedIndex = 2
        initial.triggerOffset = 8

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.dismissed) {
            $0.isOpen = false
            $0.filterText = ""
            $0.selectedIndex = 0
            $0.triggerOffset = nil
        }
    }

    // MARK: - Registry filtering contract

    func test_registry_emptyFilter_returnsAllDescriptors() {
        let r = SlashCommandRegistry.standard
        XCTAssertEqual(r.filtered(by: "").count, r.descriptors.count)
    }

    func test_registry_caseInsensitiveMatch() {
        let r = SlashCommandRegistry.standard
        let lower = r.filtered(by: "heading")
        let upper = r.filtered(by: "HEADING")
        XCTAssertEqual(lower.map(\.id), upper.map(\.id))
        XCTAssertFalse(lower.isEmpty)
    }
}
