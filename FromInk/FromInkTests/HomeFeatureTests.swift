import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for HomeFeature — Time Warp wheel, lazy brief
/// generation, and `isWarped` gating.
///
/// Substitutes `calendarContext` via `.fixed(...)` per the dates EDD
/// §12.1 pattern, and stubs `dailyBriefClient` with `LockIsolated`
/// captures so tests can both inject return values and assert which
/// dates the reducer requested.
///
/// Architectural shape exercised here (post wheel-open mode rework):
/// - `wheelToggled` (open):  isWheelOpen = true, activeBriefTab = .calendar,
///                           kicks off `fetchDayContent` (fast, no FM).
/// - `dateWarpedTo`:         updates currentDate + isWarped, kicks off
///                           `fetchDayContent` ONLY. No brief generation
///                           during scrubbing.
/// - `wheelToggled` (close): isWheelOpen = false, sends `.wheelDismissed`.
/// - `wheelDismissed`:       triggers `generateForDay` ONLY if no brief
///                           already exists for the settled day AND no
///                           generation has been attempted for it this
///                           session.
///
final class HomeFeatureTests: XCTestCase {

    /// 2026-05-13 12:00 UTC — Wednesday in NY (verified via Python).
    private let wednesday = Date(timeIntervalSince1970: 1_778_673_600)

    /// 2026-05-10 12:00 UTC — Sunday in NY (three days earlier).
    private var sunday: Date { wednesday.addingTimeInterval(-3 * 86_400) }

    // MARK: - Helpers

    /// Builds a `DailyBriefClient` stub that records calls to
    /// `fetchDayContent` and `generateForDay` and lets the test inject
    /// per-date return values. Other endpoints fatalError unless
    /// overridden — so warp tests that accidentally trigger today-refresh
    /// paths fail loudly.
    private func makeStubClient(
        dayContent: @escaping @Sendable (Date) -> DayContent = { _ in DayContent(dayKey: "") },
        generateForDay: @escaping @Sendable (Date) async throws -> DailyBriefSnapshot
            = { _ in throw CancellationError() }
    ) -> DailyBriefClient {
        DailyBriefClient(
            fetchOrGenerate: { fatalError("Wheel flow must not call fetchOrGenerate") },
            refresh: { fatalError("Wheel flow must not call refresh") },
            fetch: { _ in fatalError("Wheel flow must not call fetch") },
            calendarChanges: { AsyncStream { $0.finish() } },
            fetchDayContent: { date in dayContent(date) },
            generateForDay: { date in try await generateForDay(date) }
        )
    }

    // MARK: - wheelToggled (open leg)

    @MainActor
    func test_wheelToggled_open_activatesCalendarTab_andFetchesDayContent() async {
        let capturedDate = LockIsolated<Date?>(nil)
        let injectedContent = DayContent(
            dayKey: "2026-05-13",
            eventCount: 4,
            reminderCount: 2,
            birthdayCount: 0
        )

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                dayContent: { date in
                    capturedDate.setValue(date)
                    return injectedContent
                }
            )
        }

        await store.send(.wheelToggled) {
            $0.isWheelOpen = true
            $0.activeBriefTab = .calendar
        }

        await store.receive(.dayContentLoaded(injectedContent)) {
            $0.dayContent = injectedContent
        }

        XCTAssertEqual(
            capturedDate.value, wednesday,
            "Opening the wheel must fetch day content for the current date"
        )
    }

    // MARK: - wheelToggled (close leg) routes through wheelDismissed

    @MainActor
    func test_wheelToggled_close_sendsWheelDismissed() async {
        var seeded = HomeFeature.State(currentDate: wednesday)
        seeded.isWheelOpen = true
        seeded.activeBriefTab = .calendar
        // Already have today's brief — wheelDismissed should not regenerate.
        let todaySnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Today.",
            suggestionText: "",
            generatedAt: wednesday
        )
        seeded.briefState = .loaded(todaySnapshot)

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                generateForDay: { _ in
                    XCTFail("Must not generate when brief already exists for settled day")
                    throw CancellationError()
                }
            )
        }

        await store.send(.wheelToggled) {
            $0.isWheelOpen = false
        }

        await store.receive(.wheelDismissed)
    }

    // MARK: - dateWarpedTo

    @MainActor
    func test_dateWarpedTo_sameDay_isNoOp() async {
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient()
        }

        let sameDayDifferentSecond = wednesday.addingTimeInterval(3_600)
        await store.send(.dateWarpedTo(sameDayDifferentSecond))
    }

    @MainActor
    func test_dateWarpedTo_newDay_fetchesDayContentOnly_noBriefGeneration() async {
        let capturedDate = LockIsolated<Date?>(nil)
        let capturedGenerateDates = LockIsolated<[Date]>([])
        let injectedContent = DayContent(
            dayKey: "2026-05-10",
            eventCount: 1,
            reminderCount: 0,
            birthdayCount: 0
        )

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                dayContent: { date in
                    capturedDate.setValue(date)
                    return injectedContent
                },
                generateForDay: { date in
                    capturedGenerateDates.withValue { $0.append(date) }
                    throw CancellationError()
                }
            )
        }

        let destinationSunday = sunday
        await store.send(.dateWarpedTo(destinationSunday)) {
            $0.currentDate = destinationSunday
            $0.isWarped = true
        }

        await store.receive(.dayContentLoaded(injectedContent)) {
            $0.dayContent = injectedContent
        }

        XCTAssertEqual(
            capturedDate.value, destinationSunday,
            "Warp must request day content for the new date"
        )
        XCTAssertTrue(
            capturedGenerateDates.value.isEmpty,
            "Scrubbing must NOT trigger brief generation"
        )
    }

    @MainActor
    func test_dateWarpedTo_backToToday_clearsIsWarped() async {
        var seeded = HomeFeature.State(currentDate: sunday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                dayContent: { _ in DayContent(dayKey: "2026-05-13") }
            )
        }

        let emptyTodayContent = DayContent(dayKey: "2026-05-13")
        let backToToday = wednesday
        await store.send(.dateWarpedTo(backToToday)) {
            $0.currentDate = backToToday
            $0.isWarped = false
        }

        await store.receive(.dayContentLoaded(emptyTodayContent)) {
            $0.dayContent = emptyTodayContent
        }
    }

    // MARK: - wheelDismissed

    @MainActor
    func test_wheelDismissed_noBriefForSettledDay_triggersGeneration() async {
        let capturedDate = LockIsolated<Date?>(nil)
        let generatedSnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Freshly generated.",
            suggestionText: "",
            generatedAt: wednesday
        )

        // briefState is .empty — no brief exists for today yet.
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                generateForDay: { date in
                    capturedDate.setValue(date)
                    return generatedSnapshot
                }
            )
        }

        await store.send(.wheelDismissed)

        await store.receive(.briefGenerated(generatedSnapshot)) {
            $0.briefState = .loaded(generatedSnapshot)
        }

        XCTAssertEqual(
            capturedDate.value, wednesday,
            "Dismiss must request generation for the settled date"
        )
    }

    @MainActor
    func test_wheelDismissed_briefAlreadyExistsForSettledDay_skipsGeneration() async {
        let existingSnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Already here.",
            suggestionText: "",
            generatedAt: wednesday
        )
        var seeded = HomeFeature.State(currentDate: wednesday)
        seeded.briefState = .loaded(existingSnapshot)

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                generateForDay: { _ in
                    XCTFail("Must not generate when brief already exists for settled day")
                    throw CancellationError()
                }
            )
        }

        // No state changes, no effects.
        await store.send(.wheelDismissed)
    }

    // MARK: - isWarped gating (unchanged by this slice)

    @MainActor
    func test_calendarChanged_whileWarped_isNoOp() async {
        var seeded = HomeFeature.State(currentDate: sunday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                generateForDay: { _ in
                    XCTFail("Must not refresh while warped")
                    throw CancellationError()
                }
            )
        }

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
            $0.dailyBriefClient = makeStubClient(
                generateForDay: { _ in
                    XCTFail("Must not refresh while warped")
                    throw CancellationError()
                }
            )
        }

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

        await store.send(.briefTabTapped(.reminders)) {
            $0.activeBriefTab = .reminders
        }

        await store.send(.briefTabTapped(.birthdays)) {
            $0.activeBriefTab = .birthdays
        }
    }

    // MARK: - Settings integration

    /// Pins the load-bearing contract that
    /// `.settings(.presented(.dismissTapped))` — a delegate action
    /// from the child reducer — clears the parent's `@Presents`
    /// optional, which SwiftUI's `.sheet(item:)` translates into the
    /// dismiss animation. `SettingsFeature` itself returns `.none`
    /// for `.dismissTapped` (verified in SettingsFeatureTests); the
    /// behavior only manifests when the parent intercepts.
    ///
    /// Without this test, a refactor that accidentally drops the
    /// intercept arm in HomeFeature would fail silently — the child
    /// reducer still correctly no-ops, and only manual testing would
    /// catch that the settings X stops dismissing the sheet.
    ///
    @MainActor
    func test_settingsDismissed_viaChildDismissTap() async {
        var seeded = HomeFeature.State(currentDate: wednesday)
        seeded.settings = SettingsFeature.State()

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient()
            $0.userPreferences = .testValue
        }

        await store.send(.settings(.presented(.dismissTapped))) {
            $0.settings = nil
        }
    }

    // MARK: - Full wheel lifecycle

    /// Integration test: walks the full wheel-mode flow.
    ///
    /// 1. Wheel closed, today's brief loaded.
    /// 2. Open wheel → calendar tab auto-activates, fetchDayContent fires.
    /// 3. Scrub to past Sunday → fetchDayContent fires, NO generation.
    /// 4. Scrub back to today → fetchDayContent fires, isWarped flips off.
    /// 5. Close wheel → wheelDismissed fires; today already has a brief,
    ///    so no generation.
    ///
    @MainActor
    func test_fullWheelLifecycle() async {
        let todaySnapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Today.",
            suggestionText: "",
            generatedAt: wednesday
        )
        let todayContent = DayContent(dayKey: "2026-05-13", eventCount: 0)
        let sundayContent = DayContent(dayKey: "2026-05-10", eventCount: 2)

        let pastSunday = sunday
        let todayDate = wednesday
        var seeded = HomeFeature.State(currentDate: todayDate)
        seeded.briefState = .loaded(todaySnapshot)

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: todayDate)
            $0.dailyBriefClient = makeStubClient(
                dayContent: { date in
                    if date == pastSunday { return sundayContent }
                    return todayContent
                },
                generateForDay: { _ in
                    XCTFail("Lifecycle: today already has a brief, must not regenerate")
                    throw CancellationError()
                }
            )
        }

        // 1. Open the wheel.
        await store.send(.wheelToggled) {
            $0.isWheelOpen = true
            $0.activeBriefTab = .calendar
        }
        await store.receive(.dayContentLoaded(todayContent)) {
            $0.dayContent = todayContent
        }

        // 2. Scrub to Sunday — dayContent updates, no generation.
        await store.send(.dateWarpedTo(pastSunday)) {
            $0.currentDate = pastSunday
            $0.isWarped = true
        }
        await store.receive(.dayContentLoaded(sundayContent)) {
            $0.dayContent = sundayContent
        }

        // 3. Scrub back to today.
        await store.send(.dateWarpedTo(todayDate)) {
            $0.currentDate = todayDate
            $0.isWarped = false
        }
        await store.receive(.dayContentLoaded(todayContent)) {
            $0.dayContent = todayContent
        }

        // 4. Close wheel — wheelDismissed fires; today already has a brief.
        await store.send(.wheelToggled) {
            $0.isWheelOpen = false
        }
        await store.receive(.wheelDismissed)
    }
}
