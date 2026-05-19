import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `HomeFeature.wheelToggled` and `HomeFeature.dateWarpedTo`.
///
/// These tests substitute `calendarContext` via `.fixed(...)` per the dates EDD
/// §12.1 pattern, and stub `dailyBriefClient` with a `LockIsolated` capture so
/// the test can both inject the snapshot to return AND assert which dayKey
/// the reducer asked for.
///
final class HomeFeatureTests: XCTestCase {

    /// 2026-05-13 12:00 UTC — Wednesday in NY (verified via Python).
    private let wednesday = Date(timeIntervalSince1970: 1_778_673_600)

    /// 2026-05-10 12:00 UTC — Sunday in NY (three days earlier).
    private var sunday: Date { wednesday.addingTimeInterval(-3 * 86_400) }

    // MARK: - wheelToggled

    @MainActor
    func test_wheelToggled_flipsState() async {
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = .testValue
        }

        await store.send(.wheelToggled) {
            $0.isWheelOpen = true
        }

        await store.send(.wheelToggled) {
            $0.isWheelOpen = false
        }
    }

    // MARK: - dateWarpedTo

    @MainActor
    func test_dateWarpedTo_sameDay_isNoOp() async {
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = .testValue
        }

        // Same user-local day (different second-of-day): no state change,
        // no effect fired. TestStore enforces both invariants implicitly when
        // we omit a state-change closure.
        let sameDayDifferentSecond = wednesday.addingTimeInterval(3_600)
        await store.send(.dateWarpedTo(sameDayDifferentSecond))
    }

    @MainActor
    func test_dateWarpedTo_newDay_loadsBriefForNewDayKey() async {
        let capturedDayKey = LockIsolated<String?>(nil)
        let injectedSnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-10",
            focusText: "A bright Saturday morning.",
            suggestionText: "",
            eventCount: 0,
            reminderCount: 0,
            generatedAt: wednesday,
            highlights: []
        )

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = DailyBriefClient(
                fetchOrGenerate: { fatalError("Warp must not call fetchOrGenerate") },
                refresh: { fatalError("Warp must not call refresh") },
                fetch: { dayKey in
                    capturedDayKey.setValue(dayKey)
                    return injectedSnapshot
                },
                calendarChanges: { AsyncStream { $0.finish() } }
            )
        }

        let destinationSunday = sunday
        await store.send(.dateWarpedTo(destinationSunday)) {
            $0.currentDate = destinationSunday
            $0.isWarped = true
        }

        await store.receive(.briefLoaded(injectedSnapshot)) {
            $0.briefState = .loaded(injectedSnapshot)
        }

        XCTAssertEqual(
            capturedDayKey.value, "2026-05-10",
            "Warp must request the brief for the new day's dayKey"
        )
    }

    @MainActor
    func test_dateWarpedTo_briefNotFound_setsEmptyState() async {
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = DailyBriefClient(
                fetchOrGenerate: { fatalError() },
                refresh: { fatalError() },
                fetch: { _ in nil },     // future day with no record
                calendarChanges: { AsyncStream { $0.finish() } }
            )
        }

        let futureDate = wednesday.addingTimeInterval(7 * 86_400)
        await store.send(.dateWarpedTo(futureDate)) {
            $0.currentDate = futureDate
            $0.isWarped = true
        }

        await store.receive(.briefLoaded(nil)) {
            $0.briefState = .empty
        }
    }

    // MARK: - isWarped gating

    @MainActor
    func test_dateWarpedTo_backToToday_clearsIsWarped() async {
        let warpedStart = HomeFeature.State(currentDate: sunday)
        var seeded = warpedStart
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = DailyBriefClient(
                fetchOrGenerate: { fatalError() },
                refresh: { fatalError() },
                fetch: { _ in nil },
                calendarChanges: { AsyncStream { $0.finish() } }
            )
        }

        // Warping to "today" (Wednesday) must flip isWarped off so subsequent
        // .calendarChanged / .foregrounded actions re-arm.
        let backToToday = wednesday
        await store.send(.dateWarpedTo(backToToday)) {
            $0.currentDate = backToToday
            $0.isWarped = false
        }

        await store.receive(.briefLoaded(nil)) {
            $0.briefState = .empty
        }
    }

    @MainActor
    func test_calendarChanged_whileWarped_isNoOp() async {
        var seeded = HomeFeature.State(currentDate: sunday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = DailyBriefClient(
                fetchOrGenerate: { fatalError("Must not refresh while warped") },
                refresh: { fatalError("Must not refresh while warped") },
                fetch: { _ in nil },
                calendarChanges: { AsyncStream { $0.finish() } }
            )
        }

        // No state change, no effect fired.
        await store.send(.calendarChanged)
    }

    @MainActor
    func test_foregrounded_whileWarped_isNoOp() async {
        var seeded = HomeFeature.State(currentDate: sunday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = DailyBriefClient(
                fetchOrGenerate: { fatalError("Must not refresh while warped") },
                refresh: { fatalError("Must not refresh while warped") },
                fetch: { _ in nil },
                calendarChanges: { AsyncStream { $0.finish() } }
            )
        }

        // currentDate must stay at sunday, not auto-reset to today.
        await store.send(.foregrounded)
    }

    // MARK: - Brief tab tapping

    @MainActor
    func test_briefTabTapped_fromNil_setsActiveTab() async {
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = .testValue
        }

        await store.send(.briefTabTapped(.calendar)) {
            $0.activeBriefTab = .calendar
        }
    }

    @MainActor
    func test_briefTabTapped_sameTab_collapses() async {
        var seeded = HomeFeature.State(currentDate: wednesday)
        seeded.activeBriefTab = .calendar

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = .testValue
        }

        // Tapping the same tab collapses to nil.
        await store.send(.briefTabTapped(.calendar)) {
            $0.activeBriefTab = nil
        }
    }

    @MainActor
    func test_briefTabTapped_differentTab_swaps() async {
        var seeded = HomeFeature.State(currentDate: wednesday)
        seeded.activeBriefTab = .calendar

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = .testValue
        }

        // Tapping a different tab swaps in place — no collapse first.
        await store.send(.briefTabTapped(.reminders)) {
            $0.activeBriefTab = .reminders
        }

        await store.send(.briefTabTapped(.birthdays)) {
            $0.activeBriefTab = .birthdays
        }
    }

    // MARK: - Full warp lifecycle

    /// Integration test: walks the entire warp state machine from
    /// closed/today → wheel open → warp past → warp back to today →
    /// wheel closed. Proves the individual reducer transitions compose
    /// correctly and that `isWarped` flips correctly at each boundary.
    ///
    @MainActor
    func test_fullWarpLifecycle() async {
        let pastSnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-10",
            focusText: "Past day brief",
            suggestionText: "",
            eventCount: 0,
            reminderCount: 0,
            generatedAt: wednesday,
            highlights: []
        )
        let todaySnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Today's brief",
            suggestionText: "",
            eventCount: 0,
            reminderCount: 0,
            generatedAt: wednesday,
            highlights: []
        )

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = DailyBriefClient(
                fetchOrGenerate: { fatalError("Lifecycle only exercises .fetch") },
                refresh: { fatalError("Lifecycle only exercises .fetch") },
                fetch: { dayKey in
                    switch dayKey {
                    case "2026-05-10": return pastSnapshot
                    case "2026-05-13": return todaySnapshot
                    default: return nil
                    }
                },
                calendarChanges: { AsyncStream { $0.finish() } }
            )
        }

        // 1. Open the wheel.
        await store.send(.wheelToggled) {
            $0.isWheelOpen = true
        }

        // 2. Warp to Sunday. isWarped flips on; brief loads.
        let pastSunday = sunday
        await store.send(.dateWarpedTo(pastSunday)) {
            $0.currentDate = pastSunday
            $0.isWarped = true
        }
        await store.receive(.briefLoaded(pastSnapshot)) {
            $0.briefState = .loaded(pastSnapshot)
        }

        // 3. Warp back to today. isWarped clears; today's brief loads.
        let todayAgain = wednesday
        await store.send(.dateWarpedTo(todayAgain)) {
            $0.currentDate = todayAgain
            $0.isWarped = false
        }
        await store.receive(.briefLoaded(todaySnapshot)) {
            $0.briefState = .loaded(todaySnapshot)
        }

        // 4. Close the wheel. State returns to the initial wheel-closed
        // baseline; brief stays on today.
        await store.send(.wheelToggled) {
            $0.isWheelOpen = false
        }
    }
}
