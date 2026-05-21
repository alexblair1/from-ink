import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Home")

struct HomeFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var briefState: BriefState = .loading
        var currentDate: Date
        /// The brief header's active tab. `nil` = collapsed (tab strip
        /// only); non-nil = expanded with that tab's body showing.
        /// Replaces the legacy `isBriefExpanded` bool — "expanded" is now
        /// "has an active tab."
        var activeBriefTab: BriefTab? = nil
        var isNewNotebookSheetOpen: Bool = false
        var isRefreshing: Bool = false
        var isWheelOpen: Bool = false
        /// True iff the user has warped to a non-today day. While warped,
        /// `.foregrounded` and `.calendarChanged` are no-ops — they target
        /// "today's" brief and would clobber the warp.
        var isWarped: Bool = false
        var searchText: String = ""

        /// Fast, FM-free snapshot of the day's events/reminders/birthdays.
        /// Populated as the wheel scrubs so the tabs update without firing
        /// brief generation. `nil` until the first `dateWarpedTo` resolves.
        var dayContent: DayContent? = nil

        /// Settings overlay state. `nil` = sheet closed; non-nil =
        /// sheet presented. The optional IS the visibility flag —
        /// no parallel boolean. Driven by `@Presents` so SwiftUI's
        /// `.sheet(item:)` integration handles dismiss gestures
        /// automatically via `PresentationAction.dismiss`.
        @Presents var settings: SettingsFeature.State?

        init(currentDate: Date? = nil) {
            @Dependency(\.calendarContext) var cal
            self.currentDate = currentDate ?? cal.now()
        }
    }

    enum BriefState: Equatable {
        case loading
        case loaded(DailyBriefSnapshot)
        case empty
    }

    @CasePathable
    enum Action: Equatable {
        case appeared
        case foregrounded
        case briefLoaded(DailyBriefSnapshot?)
        case calendarChanged
        case briefRefreshed(DailyBriefSnapshot)
        /// Fires when an in-flight FM-backed refresh throws. Resets
        /// `isRefreshing` so the state can't get stuck.
        case briefRefreshFailed
        /// User tapped a brief tab. If it's already the active tab, the
        /// tab collapses (activeBriefTab = nil). Otherwise, swaps to the
        /// new tab.
        case briefTabTapped(BriefTab)
        case settingsTapped
        case newNotebookTapped
        case newNotebookDismissed
        case notebookCreated(title: String)
        case notebookTapped(id: UUID)
        /// User tapped the masthead date — open or close the Time Warp wheel.
        /// On open: switches to wheel mode (editor's note hides, calendar tab
        /// auto-activates, dayContent fetch fires for the current date).
        /// On close: routed through `wheelDismissed` so the brief-generation
        /// decision happens in one place.
        case wheelToggled
        /// User scrolled the Time Warp wheel to a new day. Updates
        /// `currentDate` and fetches `dayContent` (events/reminders/birthdays)
        /// for that day. Brief generation does NOT happen here — it happens
        /// on wheel dismiss, and only if no brief already exists for the
        /// settled day. No-op if the new date is the same user-local day as
        /// the current one (the wheel snap fires repeatedly during settle).
        case dateWarpedTo(Date)
        /// Result of `fetchDayContent(date)` after a warp. Updates state so
        /// the tab strip + body re-render with the new day's events. May be
        /// nil if the fetch is replaced by a newer warp (effect cancellation).
        case dayContentLoaded(DayContent)
        /// Fires when the wheel finishes closing (the open→closed leg of
        /// `wheelToggled`). Triggers `generateForDay` if no brief exists
        /// for `currentDate` and we haven't already attempted generation
        /// for that day-key this session.
        case wheelDismissed
        /// Result of `generateForDay(date)`. Populates `briefState` with
        /// the freshly generated brief.
        case briefGenerated(DailyBriefSnapshot)
        /// Settings child presentation. `PresentationAction` wraps the
        /// child reducer's actions plus the framework's auto-dismiss
        /// signal. The parent intercepts `.presented(.dismissTapped)`
        /// to clear `state.settings`; `.dismiss` (from SwiftUI's
        /// swipe-down gesture on the sheet) is auto-handled by
        /// `.ifLet(\.$settings, action: \.settings)`.
        case settings(PresentationAction<SettingsFeature.Action>)
    }

    @Dependency(\.dailyBriefClient) var dailyBriefClient
    @Dependency(\.calendarContext) var cal

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let dayKey = cal.dayKey(state.currentDate)
                let date = state.currentDate
                return .merge(
                    loadBrief(forDayKey: dayKey),
                    loadDayContent(for: date),
                    observeCalendarChanges()
                )

            case .foregrounded:
                // Warped users keep their warp across background→foreground.
                // Refresh logic only applies when viewing "today".
                guard !state.isWarped else { return .none }

                let now = cal.now()
                state.currentDate = now

                let newDayKey = cal.dayKey(now)
                let currentDayKey: String? = {
                    if case .loaded(let snapshot) = state.briefState {
                        return snapshot.dayKey
                    }
                    return nil
                }()

                // Always refresh dayContent on foreground — cheap EventKit
                // query, no FM. This is the belt against missed
                // `EKEventStoreChanged` notifications while the app was
                // backgrounded (e.g., user deleted an event in Calendar.app
                // and switched back). Apple's pattern is observe-AND-
                // refresh-on-foreground; we do both.
                let foregroundDate = state.currentDate
                let dayContentEffect = loadDayContent(for: foregroundDate)

                // Only fire the FM-heavy brief regen when the day actually
                // rolled over. Mid-day calendar changes are picked up via
                // `.calendarChanged` (notification) plus the dayContent
                // refresh above.
                guard currentDayKey != newDayKey else {
                    return dayContentEffect
                }

                state.isRefreshing = true
                return .merge(
                    .run { send in
                        do {
                            let snapshot = try await dailyBriefClient.fetchOrGenerate()
                            await send(.briefRefreshed(snapshot))
                        } catch {
                            log.error("Foreground refresh failed: \(error)")
                            await send(.briefRefreshFailed)
                        }
                    }
                    .cancellable(id: "briefRefresh", cancelInFlight: true),
                    dayContentEffect
                )

            case .briefLoaded(.some(let snapshot)):
                state.briefState = .loaded(snapshot)
                return .none

            case .briefLoaded(.none):
                state.briefState = .empty
                return .none

            case .calendarChanged:
                // Skip while warped — would clobber the warped brief with today's.
                guard !state.isWarped else { return .none }
                // `.cancellable(cancelInFlight:)` handles overlapping
                // refreshes correctly — no `isRefreshing` short-circuit
                // (which used to leave the flag stuck on FM failure and
                // lock out subsequent refreshes).
                state.isRefreshing = true
                let calendarChangedDate = state.currentDate
                return .merge(
                    .run { send in
                        do {
                            let snapshot = try await dailyBriefClient.fetchOrGenerate()
                            await send(.briefRefreshed(snapshot))
                        } catch {
                            log.error("Calendar refresh failed: \(error)")
                            await send(.briefRefreshFailed)
                        }
                    }
                    .cancellable(id: "briefRefresh", cancelInFlight: true),
                    loadDayContent(for: calendarChangedDate)
                )

            case .briefRefreshed(let snapshot):
                state.briefState = .loaded(snapshot)
                state.isRefreshing = false
                return .none

            case .briefRefreshFailed:
                state.isRefreshing = false
                return .none

            case .briefTabTapped(let tab):
                // Tap the active tab → collapse. Tap a different tab → swap.
                state.activeBriefTab = (state.activeBriefTab == tab) ? nil : tab
                return .none

            case .settingsTapped:
                // Presenting the sheet = optional becomes non-nil.
                // `@Presents` + `.ifLet` wires the child reducer
                // and handles framework auto-dismiss for free.
                state.settings = SettingsFeature.State()
                return .none

            // Child's delegate dismiss (user tapped X). Clear the
            // optional → SwiftUI dismisses the sheet.
            case .settings(.presented(.dismissTapped)):
                state.settings = nil
                return .none

            // SwiftUI fired auto-dismiss (swipe-down gesture).
            // `.ifLet` already cleared the optional; nothing to do.
            case .settings(.dismiss):
                return .none

            // Every other child action passes through untouched.
            case .settings:
                return .none

            case .newNotebookTapped:
                state.isNewNotebookSheetOpen = true
                return .none

            case .newNotebookDismissed:
                state.isNewNotebookSheetOpen = false
                return .none

            case .notebookCreated:
                state.isNewNotebookSheetOpen = false
                return .none

            case .notebookTapped:
                return .none

            case .wheelToggled where state.isWheelOpen:
                // Wheel is currently open → user is dismissing it.
                // Route through `wheelDismissed` so the generation
                // decision lives in one place.
                state.isWheelOpen = false
                return .send(.wheelDismissed)

            case .wheelToggled:
                // Wheel is currently closed → user is opening it.
                // Switch to wheel mode: auto-activate the calendar tab
                // (editor's note hides automatically in the view layer
                // when `isWheelOpen` is true) and refresh dayContent so
                // the tab body reflects the current day.
                state.isWheelOpen = true
                state.activeBriefTab = .calendar
                return loadDayContent(for: state.currentDate)

            case .dateWarpedTo(let newDate):
                // Same user-local day → no-op (wheel snap fires repeatedly
                // during settle; the reducer absorbs the duplicates).
                guard !cal.isSameDay(newDate, state.currentDate) else { return .none }
                state.currentDate = newDate
                // `isWarped` tracks "not viewing today". Warping back to
                // today clears the flag and re-arms .foregrounded /
                // .calendarChanged refreshes.
                state.isWarped = !cal.isToday(newDate)
                // Scrubbing fires fast `fetchDayContent` only — brief
                // generation is deferred to `wheelDismissed`. Also cancel
                // any in-flight foreground/calendar-change refresh because
                // they target "today" and would clobber the warped view.
                return .merge(
                    .cancel(id: "briefRefresh"),
                    loadDayContent(for: newDate)
                )

            case .dayContentLoaded(let content):
                state.dayContent = content
                return .none

            case .wheelDismissed:
                // Brief generation only fires if the settled day has no
                // brief in state. SwiftData cache hits are absorbed by
                // `generateForDay`'s live implementation, which short-
                // circuits to the cached record without firing FM. The
                // `.cancellable(cancelInFlight:)` on "briefRefresh"
                // absorbs rapid re-dismisses without a separate guard.
                let dayKey = cal.dayKey(state.currentDate)
                let alreadyHasBrief: Bool = {
                    if case .loaded(let snapshot) = state.briefState {
                        return snapshot.dayKey == dayKey
                    }
                    return false
                }()
                if alreadyHasBrief { return .none }
                let date = state.currentDate
                return .run { send in
                    do {
                        let snapshot = try await dailyBriefClient.generateForDay(date)
                        await send(.briefGenerated(snapshot))
                    } catch {
                        log.error("wheelDismissed: generateForDay failed — \(error)")
                    }
                }
                .cancellable(id: "briefRefresh", cancelInFlight: true)

            case .briefGenerated(let snapshot):
                state.briefState = .loaded(snapshot)
                return .none
            }
        }
        // Compose the optional SettingsFeature reducer. Runs only
        // when `state.settings` is non-nil (i.e., sheet is presented).
        // `\.$settings` projects the `@Presents` wrapper so the
        // framework can manage presentation lifecycle.
        .ifLet(\.$settings, action: \.settings) {
            SettingsFeature()
        }
    }

    // MARK: - Effects

    private func loadBrief(forDayKey dayKey: String) -> Effect<Action> {
        .run { send in
            let snapshot = await dailyBriefClient.fetch(dayKey)
            await send(.briefLoaded(snapshot))
        }
    }

    /// Pulls fresh per-date events + reminders into `state.dayContent`.
    /// Cheap, FM-free, and the canonical source for the tab body — even
    /// when the wheel is closed, since the cached brief's highlights are
    /// frozen at generation time and can lag the EventKit truth.
    private func loadDayContent(for date: Date) -> Effect<Action> {
        .run { send in
            let content = await dailyBriefClient.fetchDayContent(date)
            await send(.dayContentLoaded(content))
        }
        .cancellable(id: "dayContentFetch", cancelInFlight: true)
    }

    private func observeCalendarChanges() -> Effect<Action> {
        .run { send in
            for await _ in dailyBriefClient.calendarChanges() {
                await send(.calendarChanged)
            }
        }
        .cancellable(id: "homeCalendarObservation")
    }
}
