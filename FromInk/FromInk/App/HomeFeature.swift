import ComposableArchitecture
import Foundation
import UIKit
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

        /// `CalendarItemLink.Snapshot` keyed by `localIdentifier` for
        /// every visible event in `dayContent`. Refreshed alongside
        /// `dayContent` so the brief adapter can resolve the
        /// linked-notebook visual + tap behavior in O(1) per row.
        /// Empty until first refresh; a key being absent means
        /// "unlinked," not "unknown."
        ///
        /// Events and reminders are split because EventKit gives them
        /// distinct identifier spaces — an `EKEvent.eventIdentifier`
        /// and an `EKReminder.calendarItemIdentifier` could (in rare
        /// cases) collide as strings, and the `lookupBatch` query is
        /// scoped to a single `CalendarItemKind`. One dict per kind
        /// keeps the lookup unambiguous and the adapter reads cheap.
        var eventLinkLookup: [String: CalendarItemLink.Snapshot] = [:]
        var reminderLinkLookup: [String: CalendarItemLink.Snapshot] = [:]

        /// Branded overlay shown when the user taps an event row.
        /// Drives Create / Link / Open-in-Calendar (unlinked) or
        /// Open-linked-notebook / Open-in-Calendar (linked). Pure-data
        /// presentation — no child reducer.
        @Presents var eventActionSheet: EventActionSheetState?

        /// Notebook picker presented from the action sheet's "Link to
        /// existing" path. Modelled as a child feature so its phase
        /// state machine + notebook/page loads stay encapsulated.
        @Presents var notebookPicker: NotebookPickerFeature.State?

        /// EK-side context captured at the moment the picker is opened
        /// so the link-creation effect can stamp the right identifiers
        /// + recurrence flag without re-fetching. Cleared when the
        /// picker dismisses.
        var pendingLinkContext: PendingLinkContext? = nil

        /// Full-screen library browse surface (notebooks + folders + PDFs
        /// with search). Reuses `LibrarySearchFeature` — the same machine
        /// the future notebook-picker-with-search variant will scope. The
        /// browse-specific chrome lives in `LibraryBrowseView`.
        @Presents var libraryBrowse: LibrarySearchFeature.State?

        struct PendingLinkContext: Equatable {
            let identifier: String
            let externalIdentifier: String?
            let kind: CalendarItemKind
            let eventTitle: String
        }

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

        // MARK: - Calendar item linking

        /// User tapped a brief event row. `identifier` is the EK
        /// `eventIdentifier`. If a link exists, the reducer opens the
        /// linked notebook directly. Otherwise it presents the event
        /// action sheet.
        case eventRowTapped(identifier: String)

        /// User tapped a brief reminder row. Same routing logic as
        /// `.eventRowTapped` but the link lookup goes through
        /// `reminderLinkLookup` and the sheet's labels render the
        /// reminder variants.
        case reminderRowTapped(identifier: String)

        /// Result of the two `lookupBatch` queries that follow every
        /// `dayContentLoaded` — one per kind. Carries
        /// `localIdentifier ->` snapshot for every event AND every
        /// reminder whose link exists. The reducer writes the two
        /// halves into `eventLinkLookup` / `reminderLinkLookup` in
        /// one state mutation.
        case linkLookupRefreshed(
            events: [String: CalendarItemLink.Snapshot],
            reminders: [String: CalendarItemLink.Snapshot]
        )

        /// Action-sheet button: Create a new notebook from the event
        /// and link them. Effect chains create → link → navigate.
        case eventActionCreateTapped
        /// Action-sheet button: Link the event to an existing notebook
        /// via the picker. Effect dismisses the sheet, captures the EK
        /// context, presents `notebookPicker`.
        case eventActionLinkTapped
        /// Action-sheet button: Hand off to Apple Calendar for the
        /// underlying event (V1: opens Calendar.app to today via
        /// `calshow://`; specific-event deep link is follow-up).
        case eventActionOpenInCalendarTapped
        /// Action-sheet button (linked variant): Open the linked
        /// notebook. Same path as a direct linked-row tap.
        case eventActionOpenLinkedNotebookTapped
        /// Action-sheet dismiss (X button or scrim tap).
        case eventActionDismissed
        /// `@Presents` machinery for the action sheet. Used only for
        /// SwiftUI dismiss-gesture parity (`.dismiss`); no child
        /// reducer because the sheet has no internal state machine.
        case eventActionSheet(PresentationAction<EventActionSheetState>)

        /// Notebook picker child. The reducer scopes `\.notebookPicker`
        /// and intercepts `.presented(.delegate(.selected(...)))` to
        /// create the link + navigate, and `.presented(.delegate(.dismissed))`
        /// to clear the picker.
        case notebookPicker(PresentationAction<NotebookPickerFeature.Action>)

        /// Result of the create-notebook + create-link chain triggered
        /// by `.eventActionCreateTapped`. Reducer opens the freshly
        /// minted notebook and refreshes `linkLookup`.
        case notebookCreatedFromEvent(
            notebookID: UUID,
            notebookTitle: String,
            link: CalendarItemLink.Snapshot
        )

        /// Result of the create-link chain triggered by the picker's
        /// `.selected` delegate. Reducer opens the linked notebook and
        /// refreshes `linkLookup`.
        case linkCreated(
            notebookID: UUID,
            notebookTitle: String,
            link: CalendarItemLink.Snapshot
        )

        /// Both link-creation paths swallow service errors at the
        /// effect boundary; this action is the catch-all for telemetry
        /// + dismiss-the-sheet so the user isn't stranded. The error
        /// description is logged, not surfaced — the failure is rare
        /// enough that "tap again" is acceptable V1 recovery.
        case linkCreationFailed

        // MARK: - Library browse

        /// User tapped "VIEW ALL" in the notebook shelf header. Mints
        /// a fresh `LibrarySearchFeature.State` so the browse surface
        /// starts in a clean state every time (no leftover query from
        /// a previous open).
        case libraryBrowseRequested
        /// `@Presents` machinery for the browse child. The reducer
        /// scopes `\.libraryBrowse` so the search feature's body runs
        /// and intercepts `.presented(.delegate(.resultSelected(...)))`
        /// to route the tap into the right child presentation.
        case libraryBrowse(PresentationAction<LibrarySearchFeature.Action>)
    }

    @Dependency(\.dailyBriefClient) var dailyBriefClient
    @Dependency(\.calendarContext) var cal
    /// Clock used to debounce bursts of `EKEventStoreChanged`
    /// notifications. A user bulk-editing Calendar.app fires many
    /// notifications in <1s — without debounce we'd kick off N FM
    /// regenerations. Injected so tests can advance time with
    /// `TestClock.advance(by:)`.
    @Dependency(\.continuousClock) var clock
    @Dependency(\.calendarItemLinkService) var linkService
    @Dependency(\.notebookClient) var notebookClient

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
                // Refresh both link lookups for the items newly in
                // view. Events and reminders use distinct identifier
                // spaces, so we fire two `lookupBatch` queries — they
                // run concurrently inside the effect so the wall-clock
                // cost is one round-trip's worth.
                let eventIDs = content.events.compactMap { $0.localIdentifier }
                let reminderIDs = content.reminders.compactMap { $0.localIdentifier }
                return refreshLinkLookup(
                    eventIdentifiers: eventIDs,
                    reminderIdentifiers: reminderIDs
                )

            case let .linkLookupRefreshed(events, reminders):
                state.eventLinkLookup = events
                state.reminderLinkLookup = reminders
                return .none

            // MARK: - Calendar item linking

            case .eventRowTapped(let identifier):
                if let link = state.eventLinkLookup[identifier],
                   let notebookID = link.notebookID {
                    // Linked row: open the notebook directly. The
                    // unlinked path's action sheet would just be an
                    // extra tap here.
                    let title = link.notebookTitle
                    state.notebook = NotebookFeature.State(
                        notebookID: notebookID,
                        notebookTitle: title
                    )
                    return .none
                }
                // Unlinked row: present the action sheet. Find the
                // matching highlight so the sheet has the event title
                // and recurrence flag.
                let highlight = (state.dayContent?.events ?? [])
                    .first { $0.localIdentifier == identifier }
                state.eventActionSheet = EventActionSheetState(
                    identifier: identifier,
                    externalIdentifier: highlight?.externalIdentifier,
                    kind: .event,
                    eventTitle: highlight?.title ?? "",
                    hasRecurrenceRules: highlight?.hasRecurrenceRules ?? false,
                    linkedNotebook: nil
                )
                return .none

            case .reminderRowTapped(let identifier):
                if let link = state.reminderLinkLookup[identifier],
                   let notebookID = link.notebookID {
                    state.notebook = NotebookFeature.State(
                        notebookID: notebookID,
                        notebookTitle: link.notebookTitle
                    )
                    return .none
                }
                let highlight = (state.dayContent?.reminders ?? [])
                    .first { $0.localIdentifier == identifier }
                state.eventActionSheet = EventActionSheetState(
                    identifier: identifier,
                    externalIdentifier: highlight?.externalIdentifier,
                    kind: .reminder,
                    eventTitle: highlight?.title ?? "",
                    // Reminders use a different recurrence model that
                    // we don't (yet) decode into `hasRecurrenceRules`.
                    // Always false — the recurring-series copy
                    // therefore doesn't render on reminder sheets.
                    hasRecurrenceRules: false,
                    linkedNotebook: nil
                )
                return .none

            case .eventActionCreateTapped:
                guard let sheet = state.eventActionSheet else { return .none }
                state.eventActionSheet = nil
                return createNotebookAndLink(from: sheet)

            case .eventActionLinkTapped:
                guard let sheet = state.eventActionSheet else { return .none }
                // Capture the EK context so the picker's `.selected`
                // delegate has everything the link-creation effect
                // needs without re-fetching.
                state.pendingLinkContext = .init(
                    identifier: sheet.identifier,
                    externalIdentifier: sheet.externalIdentifier,
                    kind: sheet.kind,
                    eventTitle: sheet.eventTitle
                )
                state.eventActionSheet = nil
                state.notebookPicker = NotebookPickerFeature.State()
                return .none

            case .eventActionOpenInCalendarTapped:
                // The action name is historical (the sheet was
                // events-only in PR3); the actual destination now
                // depends on the captured kind. Reminders deep-link
                // to Reminders.app, events to Calendar.app. Neither
                // supports a documented identifier-scoped URL — both
                // open the system app to its default landing.
                let kind = state.eventActionSheet?.kind ?? .event
                state.eventActionSheet = nil
                return .run { _ in
                    let scheme: String = switch kind {
                    case .event:    "calshow://"
                    case .reminder: "x-apple-reminderkit://"
                    }
                    guard let url = URL(string: scheme) else { return }
                    await UIApplication.shared.open(url)
                }

            case .eventActionOpenLinkedNotebookTapped:
                if let linked = state.eventActionSheet?.linkedNotebook {
                    state.eventActionSheet = nil
                    state.notebook = NotebookFeature.State(
                        notebookID: linked.notebookID,
                        notebookTitle: linked.notebookTitle
                    )
                }
                return .none

            case .eventActionDismissed:
                state.eventActionSheet = nil
                return .none

            // SwiftUI auto-dismiss (cover drag etc.). `.ifLet` cleared
            // the optional already.
            case .eventActionSheet:
                return .none

            // Picker: user picked a notebook + page. Create the link
            // for the pending EK context, dismiss the picker, and open
            // the chosen notebook.
            case let .notebookPicker(.presented(.delegate(.selected(notebookID, page)))):
                guard let ctx = state.pendingLinkContext else {
                    state.notebookPicker = nil
                    return .none
                }
                state.notebookPicker = nil
                state.pendingLinkContext = nil
                return createLinkFromPicker(
                    context: ctx,
                    notebookID: notebookID,
                    page: page
                )

            case .notebookPicker(.presented(.delegate(.dismissed))):
                state.notebookPicker = nil
                state.pendingLinkContext = nil
                return .none

            case .notebookPicker:
                return .none

            case let .notebookCreatedFromEvent(notebookID, notebookTitle, link):
                writeLinkToLookup(&state, link: link)
                state.notebook = NotebookFeature.State(
                    notebookID: notebookID,
                    notebookTitle: notebookTitle
                )
                return .none

            case let .linkCreated(notebookID, notebookTitle, link):
                writeLinkToLookup(&state, link: link)
                state.notebook = NotebookFeature.State(
                    notebookID: notebookID,
                    notebookTitle: notebookTitle
                )
                return .none

            case .linkCreationFailed:
                // Logged inside the effect; nothing to surface to the
                // user here. The sheet is already gone — they can tap
                // again to retry.
                return .none

            // MARK: - Library browse

            case .libraryBrowseRequested:
                state.libraryBrowse = LibrarySearchFeature.State()
                return .none

            // Result selected → route by kind. Notebook and PDF cases
            // mirror the existing shelf-tap presentation paths;
            // folder taps are intentionally inert in V1 (browsing
            // into a folder is a future enhancement that needs its
            // own navigation state).
            case let .libraryBrowse(.presented(.delegate(.resultSelected(result)))):
                state.libraryBrowse = nil
                switch result {
                case .notebook(let snap):
                    state.notebook = NotebookFeature.State(
                        notebookID: snap.id,
                        notebookTitle: snap.title
                    )
                    // Bump `modifiedAt` so the notebook floats to the
                    // top of the shelf next render. Matches the shelf-
                    // tap path — two ways to open the same notebook
                    // shouldn't have asymmetric persistence side
                    // effects.
                    return .send(.library(.touchNotebookActivated(id: snap.id)))
                case .pdf(let snap):
                    state.pdfViewer = PDFFeature.State(
                        pdfID: snap.id,
                        title: snap.title,
                        pageCount: snap.pageCount
                    )
                case .folder:
                    // No-op for V1. A future "open folder" path would
                    // push a folder-detail destination here.
                    break
                }
                return .none

            case .libraryBrowse:
                // `.ifLet` clears the @Presents optional on framework
                // dismiss (sheet drag, etc.). Pass-through.
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
        .ifLet(\.$notebookPicker, action: \.notebookPicker) {
            NotebookPickerFeature()
        }
        .ifLet(\.$libraryBrowse, action: \.libraryBrowse) {
            LibrarySearchFeature()
        }
        // The action sheet has no child reducer — `@Presents` + a no-op
        // `ifLet`-shaped equivalent isn't needed because we never
        // forward child actions, only intercept dismiss. SwiftUI's
        // dismiss-gesture parity is achieved by the wiring view
        // observing `state.eventActionSheet`.
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

    /// Fires the two batched `lookupBatch` queries (one per kind) for
    /// the visible identifiers and folds them into a single
    /// `.linkLookupRefreshed` action. The two queries run concurrently
    /// via `async let` so the wall-clock cost matches one round-trip.
    /// Cancellable so a rapid sequence of `dayContentLoaded`s (e.g.,
    /// during a wheel scrub) collapses to one in-flight refresh.
    private func refreshLinkLookup(
        eventIdentifiers: [String],
        reminderIdentifiers: [String]
    ) -> Effect<Action> {
        .run { send in
            async let events = linkService.lookupBatch(eventIdentifiers, .event)
            async let reminders = linkService.lookupBatch(reminderIdentifiers, .reminder)
            await send(.linkLookupRefreshed(
                events: events,
                reminders: reminders
            ))
        }
        .cancellable(id: "homeLinkLookup", cancelInFlight: true)
    }

    /// Writes a freshly created `CalendarItemLink.Snapshot` into the
    /// kind-appropriate lookup dictionary. Used by both the
    /// create-from-item and link-via-picker paths so the adapter
    /// reflects the new link immediately, without waiting for the next
    /// `dayContentLoaded` cycle.
    private func writeLinkToLookup(_ state: inout State, link: CalendarItemLink.Snapshot) {
        switch link.kind {
        case .event:    state.eventLinkLookup[link.localIdentifier] = link
        case .reminder: state.reminderLinkLookup[link.localIdentifier] = link
        }
    }

    /// Create-from-event chain: mint a new notebook, write the link
    /// record, dispatch `.notebookCreatedFromEvent` on success or
    /// `.linkCreationFailed` on either step's throw.
    private func createNotebookAndLink(
        from sheet: EventActionSheetState
    ) -> Effect<Action> {
        let identifier = sheet.identifier
        let externalIdentifier = sheet.externalIdentifier
        let kind = sheet.kind
        let title = sheet.eventTitle.isEmpty
            ? AppStrings.Common.untitled
            : sheet.eventTitle
        return .run { send in
            do {
                let notebook = try await notebookClient.createNotebook(
                    title, nil, .notebook
                )
                let link = try await linkService.create(
                    identifier,
                    externalIdentifier,
                    kind,
                    notebook.id,
                    nil,
                    .createdFromItem
                )
                await send(.notebookCreatedFromEvent(
                    notebookID: notebook.id,
                    notebookTitle: notebook.title,
                    link: link
                ))
            } catch {
                log.error("createNotebookAndLink failed: \(error.localizedDescription)")
                await send(.linkCreationFailed)
            }
        }
    }

    /// Link-from-picker chain: write the link record for the picked
    /// notebook + page. `SelectedPage.lastEdited` maps to a `nil`
    /// `pageID` (caller resolves "last edited" at navigation time);
    /// `.existing(id)` maps to the picked id; `.new` mints a fresh
    /// page first, then links to that.
    private func createLinkFromPicker(
        context: State.PendingLinkContext,
        notebookID: UUID,
        page: NotebookPickerFeature.SelectedPage
    ) -> Effect<Action> {
        .run { send in
            do {
                let resolvedPageID: UUID?
                switch page {
                case .lastEdited:
                    resolvedPageID = nil
                case .existing(let pageID):
                    resolvedPageID = pageID
                case .new:
                    let page = try await notebookClient.createPage(
                        notebookID, CanvasTemplate.none.rawValue
                    )
                    resolvedPageID = page.id
                }

                let link = try await linkService.create(
                    context.identifier,
                    context.externalIdentifier,
                    context.kind,
                    notebookID,
                    resolvedPageID,
                    .linked
                )

                // Look up the notebook title so the navigation header
                // renders the right name. The picker carried it on
                // the snapshot but the value didn't ride the delegate.
                let title = (try? await notebookClient.fetchNotebook(notebookID))?
                    .notebook.title ?? AppStrings.Common.untitled

                await send(.linkCreated(
                    notebookID: notebookID,
                    notebookTitle: title,
                    link: link
                ))
            } catch {
                log.error("createLinkFromPicker failed: \(error.localizedDescription)")
                await send(.linkCreationFailed)
            }
        }
    }
}
