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
        var isImportPickerOpen: Bool = false

        /// PDF-import status alert. `nil` = nothing presented. Set when a
        /// duplicate is detected (so the user can choose to open the
        /// existing copy) or when the import flow fails.
        var importAlert: ImportAlert? = nil

        enum ImportAlert: Equatable {
            /// The picked file already existed in the library. The
            /// snapshot is the existing PDF. The alert is informational
            /// only today — opening a PDF viewer is Phase 3 work, so
            /// the action set is just "OK." When `PDFFeature` lands the
            /// alert gains an "Open" button that presents the viewer.
            case duplicate(ImportedPDFSnapshot)
            /// The import flow failed. `message` is the localized,
            /// human-readable body; alert offers "OK".
            case failed(message: String)
            /// New PDF was imported successfully. Informational
            /// confirmation; opening the viewer comes in Phase 3.
            case imported(ImportedPDFSnapshot)
        }

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

        /// Composed notebook/folder data. Owned by `LibraryFeature` —
        /// HomeWiringView reads `library.notebooks` instead of @Query.
        var library: LibraryFeature.State = LibraryFeature.State()

        /// Presented notebook state. `nil` = nothing presented; non-nil =
        /// fullScreenCover is up. `@Presents` integrates with SwiftUI's
        /// dismiss gestures via the `PresentationAction` framework so we
        /// don't need a parallel "is presenting?" bool.
        @Presents var notebook: NotebookFeature.State?

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
        /// Fires when an in-flight FM-backed refresh throws. The
        /// reducer logs and resumes — there is no transient state to
        /// roll back. Cancellation ordering is handled by `.cancellable(
        /// cancelInFlight:)` on the `briefRefresh` ID.
        case briefRefreshFailed
        /// User explicitly asked for a fresh brief (e.g., long-press on
        /// the brief card or a VoiceOver custom action). Force-bypasses
        /// the cache via `dailyBriefClient.refresh()` — the recovery
        /// path when a cache poisoning bug leaves the brief stuck on
        /// an empty record and the day hasn't rolled over.
        case briefRefreshRequested
        /// User tapped a brief tab. If it's already the active tab, the
        /// tab collapses (activeBriefTab = nil). Otherwise, swaps to the
        /// new tab.
        case briefTabTapped(BriefTab)
        case settingsTapped
        case newNotebookTapped
        case newNotebookDismissed
        case notebookCreated(title: String)
        case notebookTapped(id: UUID)

        // PDF import
        /// User tapped the import-PDF button in the top bar — open the
        /// file picker.
        case importPDFTapped
        /// User canceled the picker or it dismissed itself. Clears
        /// `isImportPickerOpen` so the binding stays consistent with
        /// SwiftUI's state.
        case importPickerDismissed
        /// User picked a PDF; forward to LibraryFeature for the actual
        /// import work.
        case importPDFPicked(URL)
        /// User dismissed the import alert via the OK button or by swipe.
        case importAlertDismissed
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

        /// Composed `LibraryFeature` actions — reads/writes notebooks
        /// + folders go through this. `Scope(state:\.library, action:\.library)`
        /// runs the child reducer; the parent intercepts
        /// `.library(.delegate(.notebookCreated(_)))` to dismiss the
        /// create sheet and present the new notebook.
        case library(LibraryFeature.Action)

        /// Presented notebook child. Same `@Presents` machinery as
        /// `settings` — `.dismiss` is auto-handled by `.ifLet`.
        case notebook(PresentationAction<NotebookFeature.Action>)
    }

    @Dependency(\.dailyBriefClient) var dailyBriefClient
    @Dependency(\.calendarContext) var cal
    /// Clock used to debounce bursts of `EKEventStoreChanged`
    /// notifications. A user bulk-editing Calendar.app fires many
    /// notifications in <1s — without debounce we'd kick off N FM
    /// regenerations. Injected so tests can advance time with
    /// `TestClock.advance(by:)`.
    @Dependency(\.continuousClock) var clock

    var body: some Reducer<State, Action> {
        Scope(state: \.library, action: \.library) {
            LibraryFeature()
        }
        Reduce { state, action in
            switch action {
            case .appeared:
                let dayKey = cal.dayKey(state.currentDate)
                let date = state.currentDate
                return .merge(
                    loadBrief(forDayKey: dayKey),
                    loadDayContent(for: date),
                    observeCalendarChanges(),
                    .send(.library(.onAppear))
                )

            case .foregrounded:
                let now = cal.now()
                let nowDayKey = cal.dayKey(now)

                // Warp doesn't survive overnight backgrounding. If the
                // user was warped to a past/future date and the real
                // calendar day has rolled while the app was suspended,
                // snap back to today and continue the normal refresh
                // path. Same-day re-foregrounds still preserve the warp
                // so a quick app switch doesn't snatch the warped view.
                if state.isWarped {
                    let warpedDayKey = cal.dayKey(state.currentDate)
                    guard warpedDayKey != nowDayKey else { return .none }
                    state.isWarped = false
                }

                state.currentDate = now

                let newDayKey = nowDayKey
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
                // Debounce: a Calendar.app bulk-edit fires many
                // `EKEventStoreChanged` events in <1s. `.cancellable(
                // cancelInFlight: true)` collapses the burst into one
                // FM call. The debounce window is short enough that
                // users don't notice the delay but long enough that
                // 3-5 rapid edits coalesce.
                let calendarChangedDate = state.currentDate
                let debounce = clock
                return .merge(
                    .run { send in
                        // `try await` (not `try?`) so a cancellation
                        // during the debounce window aborts the
                        // closure entirely instead of falling through
                        // to fetchOrGenerate. The .cancellable below
                        // catches the propagated error.
                        try await debounce.sleep(for: .seconds(1))
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
                return .none

            case .briefRefreshFailed:
                return .none

            case .briefRefreshRequested:
                // Force regen. The single-flight coordinator in the
                // client coalesces this with any in-flight `fetchOrGenerate`.
                return .run { send in
                    do {
                        let snapshot = try await dailyBriefClient.refresh()
                        await send(.briefRefreshed(snapshot))
                    } catch {
                        log.error("Manual refresh failed: \(error)")
                        await send(.briefRefreshFailed)
                    }
                }
                .cancellable(id: "briefRefresh", cancelInFlight: true)

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

            case .importPDFTapped:
                state.isImportPickerOpen = true
                return .none

            case .importPickerDismissed:
                state.isImportPickerOpen = false
                return .none

            case .importPDFPicked(let url):
                state.isImportPickerOpen = false
                return .send(.library(.importPDFRequested(url)))

            case .importAlertDismissed:
                state.importAlert = nil
                return .none

            case .notebookTapped(let id):
                // Open the notebook in the fullScreenCover and bump its
                // modifiedAt so it sorts to the top of the shelf next refresh.
                let title = state.library.notebooks
                    .first(where: { $0.id == id })?.title ?? AppStrings.Common.untitled
                state.notebook = NotebookFeature.State(notebookID: id, notebookTitle: title)
                return .send(.library(.touchNotebookActivated(id: id)))

            // Library's delegate: a notebook was just created. Dismiss the
            // create sheet and present the new notebook.
            case .library(.delegate(.notebookCreated(let snap))):
                state.isNewNotebookSheetOpen = false
                state.notebook = NotebookFeature.State(
                    notebookID: snap.id,
                    notebookTitle: snap.title
                )
                return .none

            // PDF import completed.
            case .library(.delegate(.pdfImported(let snap, let wasDuplicate))):
                // Phase 2: no PDF viewer exists yet, so success and
                // duplicate both surface as informational alerts. Phase
                // 3 (`PDFFeature`) replaces the alerts with direct
                // navigation into the viewer.
                state.importAlert = wasDuplicate
                    ? .duplicate(snap)
                    : .imported(snap)
                return .none

            case .library(.delegate(.pdfImportFailed(let message))):
                state.importAlert = .failed(message: message)
                return .none

            // Pass-through for every other library action — the Scope ran
            // the child reducer above.
            case .library:
                return .none

            // Notebook child presentation pass-through — `.dismiss` clears
            // the optional automatically via `.ifLet`.
            case .notebook:
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
        .ifLet(\.$notebook, action: \.notebook) {
            NotebookFeature()
        }
    }

    // MARK: - Effects

    /// Two-tier brief load.
    ///
    /// 1. Fast read from SwiftData via `dailyBriefClient.fetch(dayKey)`.
    ///    If a non-empty snapshot exists, we're done — dispatch
    ///    `.briefLoaded(snapshot)` and exit.
    ///
    /// 2. If the cache is missing OR holds an empty-content record
    ///    (focus + suggestion both empty — symptom of a transient FM
    ///    failure that poisoned the cache), follow up with
    ///    `dailyBriefClient.fetchOrGenerate()`. The client's hardened
    ///    predicate decides whether to actually regenerate or return
    ///    the empty cached record (e.g., FM still unavailable).
    ///
    /// This is the recovery path that lets the home screen self-heal
    /// after a botched bootstrap brief seed. Without it, an empty-
    /// cache record sits in SwiftData forever until calendar changes
    /// or the wheel dismisses on a different day.
    private func loadBrief(forDayKey dayKey: String) -> Effect<Action> {
        .run { send in
            if let snapshot = await dailyBriefClient.fetch(dayKey),
               !(snapshot.focusText.isEmpty && snapshot.suggestionText.isEmpty) {
                await send(.briefLoaded(snapshot))
                return
            }
            // Cache miss or empty content — escalate to fetchOrGenerate.
            // Dispatched as `.briefRefreshed` (not `.briefLoaded`) so
            // the existing transition path is reused. Failures fall
            // through to `.briefLoaded(nil)` so the view shows the
            // empty state rather than a stuck `.loading`.
            do {
                let snapshot = try await dailyBriefClient.fetchOrGenerate()
                await send(.briefRefreshed(snapshot))
            } catch {
                log.error("loadBrief: fetchOrGenerate failed — \(error)")
                await send(.briefLoaded(nil))
            }
        }
        .cancellable(id: "briefLoad", cancelInFlight: true)
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

    /// Subscribes to `EKEventStoreChanged` notifications, forwarding
    /// each to `.calendarChanged`. `.cancelInFlight: true` ensures
    /// re-firing `.appeared` (e.g., when a sheet dismisses and the
    /// home view re-attaches) tears down the prior subscription
    /// before starting a new one — without it, every re-appear would
    /// stack another listener.
    private func observeCalendarChanges() -> Effect<Action> {
        .run { send in
            for await _ in dailyBriefClient.calendarChanges() {
                await send(.calendarChanged)
            }
        }
        .cancellable(id: "homeCalendarObservation", cancelInFlight: true)
    }
}
