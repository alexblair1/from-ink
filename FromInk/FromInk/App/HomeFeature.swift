import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Home")

struct HomeFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var briefState: BriefState = .loading
        var currentDate: Date
        var isBriefExpanded: Bool = false
        var isSettingsOpen: Bool = false
        var isNewNotebookSheetOpen: Bool = false
        var isRefreshing: Bool = false
        var isWheelOpen: Bool = false
        /// True iff the user has warped to a non-today day. While warped,
        /// `.foregrounded` and `.calendarChanged` are no-ops — they target
        /// "today's" brief and would clobber the warp.
        var isWarped: Bool = false
        var searchText: String = ""

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
        case toggleBriefExpanded
        case settingsTapped
        case settingsDismissed
        case newNotebookTapped
        case newNotebookDismissed
        case notebookCreated(title: String)
        case notebookTapped(id: UUID)
        /// User tapped the masthead date — open or close the Time Warp wheel.
        case wheelToggled
        /// User scrolled the Time Warp wheel to a new day. Updates
        /// `currentDate` and reloads the brief for that day-key. No-op if the
        /// new date is the same user-local day as the current one.
        case dateWarpedTo(Date)
    }

    @Dependency(\.dailyBriefClient) var dailyBriefClient
    @Dependency(\.calendarContext) var cal

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let dayKey = cal.dayKey(state.currentDate)
                return .merge(
                    loadBrief(forDayKey: dayKey),
                    observeCalendarChanges()
                )

            case .foregrounded:
                // Warped users keep their warp across background→foreground.
                // Auto-refresh logic only applies when viewing "today".
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

                guard currentDayKey != newDayKey else { return .none }

                state.isRefreshing = true
                return .run { send in
                    do {
                        let snapshot = try await dailyBriefClient.fetchOrGenerate()
                        await send(.briefRefreshed(snapshot))
                    } catch {
                        log.error("Foreground refresh failed: \(error)")
                    }
                }
                .cancellable(id: "briefRefresh", cancelInFlight: true)

            case .briefLoaded(.some(let snapshot)):
                state.briefState = .loaded(snapshot)
                return .none

            case .briefLoaded(.none):
                state.briefState = .empty
                return .none

            case .calendarChanged:
                // Skip while warped — would clobber the warped brief with today's.
                guard !state.isWarped else { return .none }
                // Skip if a foreground refresh is already in-flight.
                guard !state.isRefreshing else { return .none }

                state.isRefreshing = true
                return .run { send in
                    do {
                        let snapshot = try await dailyBriefClient.fetchOrGenerate()
                        await send(.briefRefreshed(snapshot))
                    } catch {
                        log.error("Calendar refresh failed: \(error)")
                    }
                }
                .cancellable(id: "briefRefresh", cancelInFlight: true)

            case .briefRefreshed(let snapshot):
                state.briefState = .loaded(snapshot)
                state.isRefreshing = false
                return .none

            case .toggleBriefExpanded:
                state.isBriefExpanded.toggle()
                return .none

            case .settingsTapped:
                state.isSettingsOpen = true
                return .none

            case .settingsDismissed:
                state.isSettingsOpen = false
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

            case .wheelToggled:
                state.isWheelOpen.toggle()
                return .none

            case .dateWarpedTo(let newDate):
                // Same user-local day → no-op (wheel snap fires repeatedly
                // during settle; the reducer absorbs the duplicates).
                guard !cal.isSameDay(newDate, state.currentDate) else { return .none }
                state.currentDate = newDate
                // `isWarped` tracks "not viewing today". Warping back to
                // today clears the flag and re-arms .foregrounded /
                // .calendarChanged refreshes.
                state.isWarped = !cal.isToday(newDate)
                let dayKey = cal.dayKey(newDate)
                // Cancel any in-flight foreground or calendar-change refresh
                // — they target "today" and would clobber the warped brief.
                return .run { send in
                    let snapshot = await dailyBriefClient.fetch(dayKey)
                    await send(.briefLoaded(snapshot))
                }
                .cancellable(id: "briefRefresh", cancelInFlight: true)
            }
        }
    }

    // MARK: - Effects

    private func loadBrief(forDayKey dayKey: String) -> Effect<Action> {
        .run { send in
            let snapshot = await dailyBriefClient.fetch(dayKey)
            await send(.briefLoaded(snapshot))
        }
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
