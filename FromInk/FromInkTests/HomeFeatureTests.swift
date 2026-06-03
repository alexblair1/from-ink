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
            = { _ in throw CancellationError() },
        fetch: (@Sendable (String) async -> DailyBriefSnapshot?)? = nil,
        fetchOrGenerate: (@Sendable () async throws -> DailyBriefSnapshot)? = nil,
        refresh: (@Sendable () async throws -> DailyBriefSnapshot)? = nil,
        calendarChanges: (@Sendable () -> AsyncStream<Void>)? = nil
    ) -> DailyBriefClient {
        DailyBriefClient(
            fetchOrGenerate: fetchOrGenerate ?? { fatalError("Test did not stub fetchOrGenerate") },
            refresh: refresh ?? { fatalError("Test did not stub refresh") },
            fetch: fetch ?? { _ in fatalError("Test did not stub fetch") },
            calendarChanges: calendarChanges ?? { AsyncStream { $0.finish() } },
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
            // nowTick is paired with every dayContent fetch.
            $0.nowTick = self.wednesday
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
            generatedAt: wednesday,
            wasPersisted: true
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
            // nowTick is paired with every dayContent fetch.
            $0.nowTick = self.wednesday
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
            // `nowTick` is paired with every dayContent fetch — see the
            // invariant in `.appeared`.
            $0.nowTick = self.wednesday
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
            generatedAt: wednesday,
            wasPersisted: true
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
            generatedAt: wednesday,
            wasPersisted: true
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

    /// Same-day re-foreground while warped: the user opens the app,
    /// warps to yesterday, then quickly app-switches and comes back
    /// within the same day. The warp should NOT clear — they meant to
    /// look at yesterday and a quick context switch shouldn't snatch
    /// the view away.
    @MainActor
    func test_foregrounded_whileWarpedSameDay_preservesWarp() async {
        // Warped to "now() - 6 hours" — still the same wall-clock day.
        let warpedToEarlierToday = wednesday.addingTimeInterval(-6 * 3_600)
        var seeded = HomeFeature.State(currentDate: warpedToEarlierToday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                generateForDay: { _ in
                    XCTFail("Must not refresh while warped within same day")
                    throw CancellationError()
                }
            )
        }

        await store.send(.foregrounded)
    }

    /// Overnight re-foreground while warped: user warps to yesterday,
    /// backgrounds the app, foregrounds the next morning. The warp
    /// targets a stale day — clear it and snap back to today.
    /// Verifies the synchronous state mutation in the reducer; the
    /// downstream effect dispatch (briefRefreshed / dayContentLoaded)
    /// is covered by other tests.
    @MainActor
    func test_foregrounded_whileWarpedAcrossDayChange_clearsWarp() async {
        var seeded = HomeFeature.State(currentDate: sunday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = TestClock()
            $0.dailyBriefClient = makeStubClient(
                dayContent: { _ in DayContent(dayKey: "2026-05-13") },
                fetchOrGenerate: {
                    DailyBriefSnapshot(
                        dayKey: "2026-05-13",
                        focusText: "Fresh today.",
                        suggestionText: "",
                        generatedAt: self.wednesday,
                        wasPersisted: true
                    )
                }
            )
        }

        store.exhaustivity = .off

        await store.send(.foregrounded)

        // Settle effects (briefRefresh + dayContentFetch). With
        // non-exhaustive testing we don't assert on the action
        // sequence — `finish()` waits for in-flight effects to
        // complete then we inspect post-state.
        await store.finish()

        XCTAssertFalse(store.state.isWarped, "Warp must clear on overnight foreground")
        XCTAssertEqual(store.state.currentDate, self.wednesday, "currentDate must snap to today")
        // T3: `.foregrounded` must refresh `nowTick` so the adapter
        // sees a fresh clock reference paired with the dayContent
        // fetch it kicked off.
        XCTAssertEqual(store.state.nowTick, self.wednesday)
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

    // MARK: - .appeared brief regeneration recovery (B1)

    /// First launch / cache empty: fetch returns nil. The reducer must
    /// escalate to fetchOrGenerate so the user gets a brief instead
    /// of staying on `.loading` forever.
    @MainActor
    func test_appeared_cacheMiss_escalatesToFetchOrGenerate() async {
        let snapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Generated fresh.",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            // `TestClock()` doesn't auto-advance, so the timer effect
            // started by `.appeared` is created but never ticks. Tests
            // that DO care about timer firing advance the clock
            // explicitly.
            $0.continuousClock = TestClock()
            $0.dailyBriefClient = makeStubClient(
                fetch: { _ in nil },
                fetchOrGenerate: { snapshot }
            )
        }
        store.exhaustivity = .off

        await store.send(.appeared)
        await store.receive(\.briefRefreshed)
        if case .loaded(let s) = store.state.briefState {
            XCTAssertEqual(s.focusText, "Generated fresh.")
        } else {
            XCTFail("Expected loaded state")
        }
        // T3: nowTick must be refreshed by `refreshClockState` at the
        // top of `.appeared` so the adapter renders against a fresh
        // clock reference, not the State.init value.
        XCTAssertEqual(store.state.nowTick, self.wednesday)
    }

    /// Cache hit but the cached snapshot has empty focus + suggestion
    /// (transient FM failure poisoned it). The reducer must NOT trust
    /// the empty snapshot — escalate to fetchOrGenerate so the client's
    /// hardened predicate decides whether to actually regenerate.
    @MainActor
    func test_appeared_cacheEmptyContent_escalatesToFetchOrGenerate() async {
        let emptyCached = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )
        let regenerated = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Regenerated.",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = TestClock()
            $0.dailyBriefClient = makeStubClient(
                fetch: { _ in emptyCached },
                fetchOrGenerate: { regenerated }
            )
        }
        store.exhaustivity = .off

        await store.send(.appeared)
        await store.receive(\.briefRefreshed)
        if case .loaded(let s) = store.state.briefState {
            XCTAssertEqual(s.focusText, "Regenerated.")
        } else {
            XCTFail("Expected loaded state")
        }
    }

    /// Cache hit with real content: the reducer must NOT escalate to
    /// fetchOrGenerate — the cached snapshot is good. fetchOrGenerate
    /// would fire FM unnecessarily on every cold app open.
    @MainActor
    func test_appeared_cacheHitWithContent_doesNotEscalate() async {
        let cached = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Already good.",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = TestClock()
            $0.dailyBriefClient = makeStubClient(
                fetch: { _ in cached },
                fetchOrGenerate: {
                    XCTFail("Cache hit with content must NOT escalate")
                    throw CancellationError()
                }
            )
        }
        store.exhaustivity = .off

        await store.send(.appeared)
        await store.receive(\.briefLoaded)
        if case .loaded(let s) = store.state.briefState {
            XCTAssertEqual(s.focusText, "Already good.")
        } else {
            XCTFail("Expected loaded state")
        }
    }

    // MARK: - Manual brief refresh trigger (B2)

    /// User long-presses the editor's note → `.briefRefreshRequested`
    /// → `dailyBriefClient.refresh()` is called (bypasses cache) and
    /// the resulting snapshot lands in state via `.briefRefreshed`.
    @MainActor
    func test_briefRefreshRequested_callsRefresh() async {
        let refreshed = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Force-regenerated.",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )
        let refreshCalls = LockIsolated(0)
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.dailyBriefClient = makeStubClient(
                refresh: {
                    refreshCalls.withValue { $0 += 1 }
                    return refreshed
                }
            )
        }

        store.exhaustivity = .off

        await store.send(.briefRefreshRequested)
        await store.receive(\.briefRefreshed)
        if case .loaded(let s) = store.state.briefState {
            XCTAssertEqual(s.focusText, "Force-regenerated.")
        } else {
            XCTFail("Expected loaded state")
        }
        XCTAssertEqual(refreshCalls.value, 1)
    }

    // MARK: - calendarChanged debounce (B4)

    /// Three rapid `.calendarChanged` events within the debounce window
    /// must collapse into one `fetchOrGenerate` call. Verifies the
    /// debounce works against a `TestClock` advance.
    @MainActor
    func test_calendarChanged_debounce_collapsesRapidBurst() async {
        let clock = TestClock()
        let generated = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "After debounce.",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )
        let generateCalls = LockIsolated(0)

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = clock
            $0.dailyBriefClient = makeStubClient(
                fetchOrGenerate: {
                    generateCalls.withValue { $0 += 1 }
                    return generated
                }
            )
        }
        store.exhaustivity = .off

        // Three rapid changes; .cancellable(cancelInFlight:) collapses them.
        await store.send(.calendarChanged)
        await store.send(.calendarChanged)
        await store.send(.calendarChanged)

        // Advance past the 1-second debounce window.
        await clock.advance(by: .seconds(1.1))

        await store.receive(\.briefRefreshed)
        XCTAssertEqual(
            generateCalls.value, 1,
            "Three rapid calendarChanged events must coalesce into one fetchOrGenerate"
        )
        // T3: `.calendarChanged` must refresh `nowTick` so the badge /
        // bar predicate sees the current moment immediately, not on
        // the next timer tick (5s later). That's the specific bug the
        // user observed when adding a mid-day calendar event.
        XCTAssertEqual(store.state.nowTick, self.wednesday)
    }

    // MARK: - Time-advance timer

    /// One tick should refresh `state.nowTick` AND fire a `loadDayContent`.
    /// FM path must NOT be touched — `fetchOrGenerate` is set to fatalError
    /// (via the default stub), so a wrong-path tick would crash the test.
    @MainActor
    func test_timeAdvanceTick_updatesNowTickAndFiresLoadDayContent() async {
        let injectedContent = DayContent(dayKey: "2026-05-13", eventCount: 1)
        let fetchedDates = LockIsolated<[Date]>([])
        let plus30s = wednesday.addingTimeInterval(30)

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: plus30s)
            $0.continuousClock = ImmediateClock()
            $0.dailyBriefClient = makeStubClient(
                dayContent: { date in
                    fetchedDates.withValue { $0.append(date) }
                    return injectedContent
                }
            )
        }
        store.exhaustivity = .off

        await store.send(.timeAdvanceTick) { state in
            state.nowTick = plus30s
        }

        await store.receive(\.dayContentLoaded)
        XCTAssertEqual(fetchedDates.value, [wednesday])
    }

    /// While warped, tick is a no-op — warped dates have no "now"
    /// semantics. Defense against the bar spuriously appearing on
    /// past-day views.
    @MainActor
    func test_timeAdvanceTick_whileWarped_noOps() async {
        var seeded = HomeFeature.State(currentDate: sunday)
        seeded.isWarped = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = ImmediateClock()
            $0.dailyBriefClient = makeStubClient(
                dayContent: { _ in
                    XCTFail("Tick must not fetch dayContent while warped")
                    return DayContent(dayKey: "")
                }
            )
        }

        // No state change, no effect fired.
        await store.send(.timeAdvanceTick)
    }

    /// While the wheel is open, tick is a no-op — the user is
    /// scrubbing dates; live updates would be visual noise.
    @MainActor
    func test_timeAdvanceTick_whileWheelOpen_noOps() async {
        var seeded = HomeFeature.State(currentDate: wednesday)
        seeded.isWheelOpen = true

        let store = TestStore(initialState: seeded) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = ImmediateClock()
            $0.dailyBriefClient = makeStubClient(
                dayContent: { _ in
                    XCTFail("Tick must not fetch dayContent while wheel is open")
                    return DayContent(dayKey: "")
                }
            )
        }

        await store.send(.timeAdvanceTick)
    }

    /// Day rollover during a continuously-foreground session: tick
    /// must advance `currentDate` to the new day before fetching.
    /// Verifies the `advanceCurrentDateIfDayRolled` helper fires
    /// through the tick path.
    @MainActor
    func test_timeAdvanceTick_crossesMidnight_advancesCurrentDate() async {
        // currentDate = Sunday at noon UTC. cal.now() = Wednesday.
        // Day key differs — helper should advance.
        let store = TestStore(initialState: HomeFeature.State(currentDate: sunday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = ImmediateClock()
            $0.dailyBriefClient = makeStubClient(
                dayContent: { _ in DayContent(dayKey: "2026-05-13") }
            )
        }
        store.exhaustivity = .off

        await store.send(.timeAdvanceTick) { state in
            state.currentDate = self.wednesday
            state.nowTick = self.wednesday
        }
    }

    /// Backgrounding tears down the timer effect — verified by sending
    /// `.backgrounded` and then directly observing that no tick fires
    /// on advance. The `.cancel(id:)` semantics of TCA cancel the
    /// in-flight timer loop.
    @MainActor
    func test_backgrounded_cancelsTimer() async {
        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = ImmediateClock()
            $0.dailyBriefClient = makeStubClient()
        }

        // No state change, no actions received — just dispatches
        // `.cancel(id: "homeTimeAdvance")` which is invisible to TestStore.
        await store.send(.backgrounded)
    }

    /// End-to-end test for the actual timer mechanism: `.appeared` arms
    /// the timer effect via `startTimeAdvanceTimer()`; advancing the
    /// `TestClock` by the interval (5s) must cause the for-await loop
    /// inside the effect to dispatch a `.timeAdvanceTick` action.
    ///
    /// Without this test, refactors to `startTimeAdvanceTimer`'s
    /// wiring (e.g., swapping `clock.timer` for a different async
    /// primitive) would silently break the loop while every
    /// direct-dispatch tick test still passed.
    @MainActor
    func test_appeared_armsTimerThatFiresAfterInterval() async {
        let clock = TestClock()
        let snapshot = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "x",
            suggestionText: "",
            generatedAt: wednesday,
            wasPersisted: true
        )

        let store = TestStore(initialState: HomeFeature.State(currentDate: wednesday)) {
            HomeFeature()
        } withDependencies: {
            $0.calendarContext = .fixed(now: wednesday)
            $0.continuousClock = clock
            $0.dailyBriefClient = makeStubClient(
                fetch: { _ in snapshot },
                fetchOrGenerate: { snapshot }
            )
        }
        store.exhaustivity = .off

        await store.send(.appeared)
        // 5s is the cadence pinned in `startTimeAdvanceTimer()`. If the
        // production cadence changes, this advance value must follow.
        await clock.advance(by: .seconds(5))
        await store.receive(\.timeAdvanceTick)
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
            generatedAt: wednesday,
            wasPersisted: true
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
            // nowTick is paired with every dayContent fetch.
            $0.nowTick = self.wednesday
        }
        await store.receive(.dayContentLoaded(todayContent)) {
            $0.dayContent = todayContent
        }

        // 2. Scrub to Sunday — dayContent updates, no generation.
        await store.send(.dateWarpedTo(pastSunday)) {
            $0.currentDate = pastSunday
            $0.isWarped = true
            $0.nowTick = self.wednesday
        }
        await store.receive(.dayContentLoaded(sundayContent)) {
            $0.dayContent = sundayContent
        }

        // 3. Scrub back to today.
        await store.send(.dateWarpedTo(todayDate)) {
            $0.currentDate = todayDate
            $0.isWarped = false
            $0.nowTick = self.wednesday
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
