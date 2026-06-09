import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// Reducer-level coverage for the slash command palette:
///
///   • `openRequested` clears filter, resets selection, populates the
///     matched list from the registry.
///   • `filterChanged` recomputes `matchedCommands` via
///     `localizedStandardContains` and clamps `selectedIndex` so a
///     narrowed list doesn't leave selection pointing past the end.
///   • `keyboardNavigationKey` moves `selectedIndex` within bounds;
///     enter dispatches `commandSelected` for the current highlight;
///     escape dismisses.
///   • `commandSelected` closes the palette (so consecutive commands
///     don't queue against a stale popover).
///   • `dismissed` clears all transient state.
final class SlashCommandPaletteFeatureTests: XCTestCase {

    // MARK: - openRequested

    @MainActor
    func test_openRequested_seedsMatchedListAndResetsSelection() async {
        let store = TestStore(
            initialState: SlashCommandPaletteFeature.State(),
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.openRequested) {
            $0.isOpen = true
            $0.filterText = ""
            $0.matchedCommands = SlashCommandRegistry.standard().descriptors
            $0.selectedIndex = 0
        }
    }

    // MARK: - filterChanged narrows + clamps

    @MainActor
    func test_filterChanged_narrowsMatchedList() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors

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
            SlashCommandRegistry.standard().descriptors.count
        )
    }

    @MainActor
    func test_filterChanged_clampsSelectedIndexWhenListShrinks() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors
        // Position cursor at the end of the full list — well past
        // whatever a narrow filter will return.
        initial.selectedIndex = initial.matchedCommands.count - 1

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.filterChanged("heading"))

        XCTAssertLessThan(
            store.state.selectedIndex,
            store.state.matchedCommands.count,
            "selectedIndex must clamp to the narrowed list"
        )
        XCTAssertGreaterThanOrEqual(store.state.selectedIndex, 0)
    }

    // MARK: - keyboard navigation

    @MainActor
    func test_keyboardNavigation_arrowDown_advancesSelection() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors
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
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors
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
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors
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
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors
        // Index 1 in the standard registry is heading2 — pin that
        // assumption with the assertion below.
        initial.selectedIndex = 1

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        XCTAssertEqual(initial.matchedCommands[1].id, .heading2)

        await store.send(.keyboardNavigationKey(.enter))
        await store.receive(.commandSelected(.heading2)) {
            $0.isOpen = false
            $0.selectedIndex = 0
            $0.filterText = ""
        }
    }

    @MainActor
    func test_keyboardNavigation_escape_dispatchesDismissed() async {
        var initial = SlashCommandPaletteFeature.State()
        initial.isOpen = true
        initial.matchedCommands = SlashCommandRegistry.standard().descriptors

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
        initial.matchedCommands = SlashCommandRegistry.standard().filtered(by: "head")
        initial.selectedIndex = 2

        let store = TestStore(
            initialState: initial,
            reducer: { SlashCommandPaletteFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.dismissed) {
            $0.isOpen = false
            $0.filterText = ""
            $0.selectedIndex = 0
        }
    }

    // MARK: - Registry filtering contract

    func test_registry_emptyFilter_returnsAllDescriptors() {
        let r = SlashCommandRegistry.standard()
        XCTAssertEqual(r.filtered(by: "").count, r.descriptors.count)
    }

    func test_registry_caseInsensitiveMatch() {
        let r = SlashCommandRegistry.standard()
        let lower = r.filtered(by: "heading")
        let upper = r.filtered(by: "HEADING")
        XCTAssertEqual(lower.map(\.id), upper.map(\.id))
        XCTAssertFalse(lower.isEmpty)
    }
}
