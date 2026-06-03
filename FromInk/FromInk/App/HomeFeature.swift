import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
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

        /// Document acquisition surface (file picker OR camera scan).
        /// `nil` = the choice popover is closed; non-nil = it's
        /// presented. Reusable: same `@Presents` + `DocumentImportFeature`
        /// pattern can be mounted anywhere else (Notebook etc.).
        /// Owns its own state machine; HomeFeature only intercepts
        /// the `.delegate(.acquired)` output to route the resulting
        /// PDF into LibraryFeature.
        @Presents var documentImport: DocumentImportFeature.State?

        /// PDF-import status alert. `nil` = nothing presented. Set when a
        /// duplicate is detected (so the user can choose to open the
        /// existing copy) or when the import flow fails.
        var importAlert: ImportAlert? = nil

        enum ImportAlert: Equatable {
            /// The picked file already existed in the library. The
            /// snapshot is the existing PDF; the alert offers "Open"
            /// (present the viewer for the existing copy) and
            /// "Cancel" (dismiss without navigating).
            case duplicate(ImportedPDFSnapshot)
            /// The import flow failed. `message` is the localized,
            /// human-readable body; alert offers "OK".
            case failed(message: String)
        }

        var isWheelOpen: Bool = false
        /// True iff the user has warped to a non-today day. While warped,
        /// `.foregrounded` and `.calendarChanged` are no-ops — they target
        /// "today's" brief and would clobber the warp.
        var isWarped: Bool = false
        /// Focus mode hides the editor's note + the calendar tab body
        /// so the home screen reduces to the masthead + notebook shelf.
        /// User-toggled via the eye / eye.slash button in the top bar.
        /// Ephemeral — does not persist across app launches.
        var isFocusMode: Bool = false
        var searchText: String = ""

        /// Fast, FM-free snapshot of the day's events/reminders/birthdays.
        /// Populated as the wheel scrubs so the tabs update without firing
        /// brief generation. `nil` until the first `dateWarpedTo` resolves.
        var dayContent: DayContent? = nil

        /// Clock reference used by the home adapter to derive time-
        /// relative UI (currently the per-event in-progress indicator
        /// on `BriefEventRow`). Updated by `.timeAdvanceTick` every
        /// 60 seconds while the scene is active. Reading state for
        /// "now" — rather than `cal.now()` directly in the adapter —
        /// keeps SwiftUI's render path deterministic: every tick
        /// mutates state → view body re-runs → adapter recomputes
        /// in-progress flags against the fresh reference.
        var nowTick: Date

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

        /// Presented PDF viewer state. Same `@Presents` machinery as
        /// `notebook`; presented as a fullScreenCover. Set on
        /// successful new-PDF import, on Recent shelf tap, or on the
        /// duplicate-alert's Open button. Mutually exclusive with
        /// `notebook` in practice — the UI surfaces only emit one at
        /// a time.
        @Presents var pdfViewer: PDFFeature.State?

        init(currentDate: Date? = nil) {
            @Dependency(\.calendarContext) var cal
            let resolved = currentDate ?? cal.now()
            self.currentDate = resolved
            // Initialize `nowTick` to the same moment as `currentDate`
            // so the adapter's first render has a sensible "now"
            // reference even before the first timer tick lands.
            self.nowTick = resolved
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
        /// SwiftUI scene phase became `.background` or `.inactive`.
        /// Tears down the time-advance timer so we don't wake the
        /// device while suspended. The timer is re-armed by the next
        /// `.foregrounded`.
        case backgrounded
        /// One tick of the once-a-minute time-advance loop. Refreshes
        /// `state.nowTick` (drives the per-event in-progress indicator)
        /// and re-fetches `dayContent` so `trailingBadge` strings
        /// ("In 30 m" → "In 29 m") stay current. Stays in the FM-free
        /// pipeline — never invokes `fetchOrGenerate`.
        case timeAdvanceTick
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
        /// User tapped the eye / eye.slash button in the top bar.
        /// Toggles `isFocusMode` and collapses any active brief tab so
        /// the user returns to a clean expanded state on exit.
        case focusModeToggled
        case newNotebookTapped
        case newNotebookDismissed
        case notebookCreated(title: String)
        case notebookTapped(id: UUID)

        // Document acquisition — Menu items in the top bar each
        // dispatch one of these. The choice (import vs scan) lives
        // in the Menu chrome; this reducer just opens the correct
        // system surface.
        /// User tapped "Import file" in the doc-icon pull-down menu.
        case importPDFTapped
        /// User tapped "Scan document" in the doc-icon pull-down menu.
        case scanDocumentTapped
        /// `@Presents` machinery for the document-import child.
        /// Auto-handled by `.ifLet(\.$documentImport, ...)`; HomeFeature
        /// only inspects `.presented(.delegate(...))` to route the
        /// result into `LibraryFeature` (or to clear state on cancel).
        case documentImport(PresentationAction<DocumentImportFeature.Action>)
        /// User dismissed the import alert via the OK / Cancel button
        /// or by swipe.
        case importAlertDismissed
        /// User tapped "Open" on the duplicate alert — present the
        /// existing PDF in the viewer.
        case importAlertOpenTapped

        // PDF viewer
        /// User tapped a card in the home Recent PDFs shelf —
        /// present `PDFFeature` for that id. The snapshot is looked
        /// up from `library.recentPDFs`; if it vanished between
        /// render and tap (delete race) the action is a no-op.
        case pdfCardTapped(id: UUID)
        /// Presented PDF viewer child. Same `@Presents` machinery as
        /// `notebook`; `.dismiss` is auto-handled by `.ifLet`.
        case pdfViewer(PresentationAction<PDFFeature.Action>)
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
                // Single-call helper: captures one `now`, conditionally
                // advances `currentDate` if the day rolled, and writes
                // `nowTick`. See the helper's docs for the invariant.
                refreshClockState(&state)
                let dayKey = cal.dayKey(state.currentDate)
                let date = state.currentDate
                return .merge(
                    loadBrief(forDayKey: dayKey),
                    loadDayContent(for: date),
                    observeCalendarChanges(),
                    startTimeAdvanceTimer(),
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
                // Pair the clock reference with the dayContent fetch
                // below — see `.appeared` for the invariant.
                state.nowTick = now

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

                // (Re)arm the time-advance timer on every foreground
                // entry. `.cancellable(cancelInFlight: true)` makes this
                // idempotent — restart while already running just
                // tears down the previous loop and starts a fresh one.
                let timerEffect = startTimeAdvanceTimer()

                // Only fire the FM-heavy brief regen when the day actually
                // rolled over. Mid-day calendar changes are picked up via
                // `.calendarChanged` (notification) plus the dayContent
                // refresh above.
                guard currentDayKey != newDayKey else {
                    return .merge(dayContentEffect, timerEffect)
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
                    dayContentEffect,
                    timerEffect
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
                // EventKit notifications can fire at any time, including
                // past midnight in a continuously-foreground app. The
                // helper advances `currentDate` AND refreshes `nowTick`
                // with one `cal.now()` capture so an in-progress event
                // added mid-day flips its bar immediately, not on the
                // next timer tick.
                refreshClockState(&state)
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

            case .backgrounded:
                // Tear down the time-advance loop while suspended so
                // we don't wake the device for ticks the user can't
                // see. `.foregrounded` re-arms it on return.
                return .cancel(id: "homeTimeAdvance")

            case .timeAdvanceTick:
                // The minute-granularity clock pulse. Guarded so the
                // path stays cheap when the view is in a state where
                // a refresh would be visual noise.
                //
                // Stays FM-free: calls `loadDayContent` only. No
                // `fetchOrGenerate`, no SwiftData write, no FM. The
                // tick body is verified by `test_timeAdvanceTick_
                // doesNotCallFetchOrGenerate`.
                guard !state.isWarped else { return .none }
                guard !state.isWheelOpen else { return .none }
                // Helper captures one `now`, advances `currentDate`
                // if the day rolled (catches continuously-foreground
                // sessions crossing midnight), and writes `nowTick`
                // so the adapter re-renders against the fresh clock.
                refreshClockState(&state)
                return loadDayContent(for: state.currentDate)

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

            case .focusModeToggled:
                state.isFocusMode.toggle()
                // Collapse any expanded tab so the view returns to a
                // clean tab-strip state when focus mode is later
                // disabled. Without this, exiting focus would re-reveal
                // whichever tab body was last active, which feels like
                // a state leak across the focus boundary.
                state.activeBriefTab = nil
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
                // Open the file picker directly. The Menu in
                // HomeTopBar handled the choice; this is the
                // "I want to import a file" branch.
                state.documentImport = DocumentImportFeature.State(
                    initialPhase: .filePicker
                )
                return .none

            case .scanDocumentTapped:
                // Open the scanner directly. Menu only offers this
                // item when VNDocumentCameraViewController.isSupported
                // is true, so by the time we get here scanning is
                // guaranteed to be available.
                state.documentImport = DocumentImportFeature.State(
                    initialPhase: .scanning
                )
                return .none

            // Child delegate: document acquired. Route into LibraryFeature
            // using the source-appropriate entry point and clear the
            // child presentation. Destination logic stays in Home;
            // acquisition logic stays in DocumentImportFeature.
            case let .documentImport(.presented(.delegate(.acquired(source, fileURL, pdfData)))):
                state.documentImport = nil
                switch source {
                case .file:
                    guard let fileURL else { return .none }
                    return .send(.library(.importPDFRequested(fileURL)))
                case .scan(let pageCount):
                    guard let pdfData else { return .none }
                    return .send(.library(.importPDFFromData(
                        pdfData,
                        suggestedName: AppStrings.Library.scanFallbackTitle(pageCount: pageCount)
                    )))
                }

            // Child delegate: user cancelled the file picker / scanner
            // or acknowledged an error. Clear the presentation so the
            // menu can be re-opened cleanly.
            case .documentImport(.presented(.delegate(.dismissed))):
                state.documentImport = nil
                return .none

            // SwiftUI auto-dismiss (cover drag etc.). `.ifLet` cleared
            // the optional already; nothing to do here.
            case .documentImport(.dismiss):
                return .none

            // All other child actions pass through untouched.
            case .documentImport:
                return .none

            case .importAlertDismissed:
                state.importAlert = nil
                return .none

            case .importAlertOpenTapped:
                // Only the duplicate alert offers Open. Pull the
                // snapshot off the alert state and present the viewer.
                if case .duplicate(let snap) = state.importAlert {
                    state.pdfViewer = PDFFeature.State(
                        pdfID: snap.id,
                        title: snap.title,
                        pageCount: snap.pageCount
                    )
                }
                state.importAlert = nil
                return .none

            case .pdfCardTapped(let id):
                // Look up the snapshot in the recent list so the
                // viewer has title + page count ready before bytes
                // load. Delete race (the row vanished between render
                // and tap) is a no-op rather than a crash.
                guard let snap = state.library.recentPDFs.first(where: { $0.id == id }) else {
                    return .none
                }
                state.pdfViewer = PDFFeature.State(
                    pdfID: snap.id,
                    title: snap.title,
                    pageCount: snap.pageCount
                )
                return .none

            // PDF viewer dismiss — clear the @Presents slot.
            case .pdfViewer(.presented(.dismissTapped)):
                state.pdfViewer = nil
                return .none

            // SwiftUI fired auto-dismiss (swipe-down or interactive
            // dismiss). `.ifLet` cleared the optional already.
            case .pdfViewer(.dismiss):
                return .none

            // Pass-through for every other PDF viewer action.
            case .pdfViewer:
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
                if wasDuplicate {
                    // Re-import of an existing PDF — surface an alert so
                    // the user can confirm the navigation rather than
                    // being silently dropped into a viewer for a file
                    // they didn't realize was already there.
                    state.importAlert = .duplicate(snap)
                } else {
                    // New import — the user explicitly chose this file;
                    // auto-present the viewer. No alert.
                    state.pdfViewer = PDFFeature.State(
                        pdfID: snap.id,
                        title: snap.title,
                        pageCount: snap.pageCount
                    )
                }
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
                // Helper advances `currentDate` if the day rolled
                // (without this, opening the wheel after midnight in
                // a continuously-foreground session would center it
                // on yesterday) AND refreshes `nowTick` for the
                // adapter — both with one `cal.now()` capture.
                refreshClockState(&state)
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
                // Refresh clock reference. Warped views render
                // isInProgress=false for everything (no event satisfies
                // start <= now < end on a non-today date), but keeping
                // the invariant intact avoids needing special-case logic
                // in the adapter.
                state.nowTick = cal.now()
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
        .ifLet(\.$pdfViewer, action: \.pdfViewer) {
            PDFFeature()
        }
        .ifLet(\.$documentImport, action: \.documentImport) {
            DocumentImportFeature()
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

    /// Tick loop that drives `state.nowTick` so the per-event
    /// in-progress indicator + trailing badge stay accurate as time
    /// elapses. Cancellable so `.backgrounded` can tear it down — we
    /// don't want to wake the device for ticks the user can't see.
    /// `.foregrounded` re-arms with `cancelInFlight: true`, so restart
    /// is idempotent.
    ///
    /// **Cadence rationale (5 seconds).** EventKit doesn't notify when
    /// an event "starts" or "ends" — only on user edits. So the bar
    /// and badge cross start/end boundaries entirely on this tick.
    /// At 60s the user observed a visibly stale "Now" pill on
    /// just-ended meetings. 5s caps that lag at ~5s while still being
    /// dirt cheap: each tick is a sub-millisecond EventKit fetch plus
    /// an adapter recompute. Smart-scheduling (fire one tick at the
    /// next start/end moment) would be more precise + cheaper but
    /// adds complexity; deferred until the polling cost becomes
    /// measurable.
    ///
    /// `clock.timer(interval:)` returns an `AsyncStream<Instant>` that
    /// drains forever; the for-await loop consumes it until the effect
    /// is cancelled. Pure suspension when no work is due.
    private func startTimeAdvanceTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(5)) {
                await send(.timeAdvanceTick)
            }
        }
        .cancellable(id: "homeTimeAdvance", cancelInFlight: true)
    }

    /// Refreshes time-anchored state for any action that's about to
    /// dispatch a `loadDayContent` for "today":
    ///
    ///   1. Captures `cal.now()` exactly once.
    ///   2. Advances `state.currentDate` if the device day rolled
    ///      since it was last set (no-op while warped; warped dates
    ///      have no live "today" semantics).
    ///   3. Refreshes `state.nowTick` to the captured now so the
    ///      adapter's in-progress predicate sees a clock reference
    ///      aligned with the fetch we're about to kick off.
    ///
    /// **Single-`now` invariant.** Per `dates_edd.md` §3, every logical
    /// instant should resolve through one `cal.now()` call. The
    /// previous design called `cal.now()` twice at each site (once
    /// inside the day-rollover helper, once for `nowTick`) — close
    /// enough in practice but a correctness hole around midnight
    /// microsecond boundaries. Folding into one helper closes it.
    ///
    /// Called at the top of `.appeared`, `.calendarChanged`,
    /// `.timeAdvanceTick`, and `.wheelToggled` (open leg).
    ///
    /// **Exempt:** `.foregrounded` keeps its own path — its contract
    /// is "unconditional refresh," which differs from the day-rolled
    /// guard. `.dateWarpedTo` keeps a standalone `state.nowTick =
    /// cal.now()` since `currentDate` is being set by the user's
    /// explicit choice.
    private func refreshClockState(_ state: inout State) {
        let now = cal.now()
        if !state.isWarped && cal.dayKey(state.currentDate) != cal.dayKey(now) {
            state.currentDate = now
        }
        state.nowTick = now
    }
}
