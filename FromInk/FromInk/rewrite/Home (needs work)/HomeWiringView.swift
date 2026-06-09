import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// Wiring view for the home screen. Reads notebooks/folders from the
/// composed `LibraryFeature` substate; the days of `@Query` + direct
/// `modelContext` mutation are gone — all writes go through
/// `NotebookClient` via `LibraryFeature` actions.
///
struct HomeWiringView: View {
    /// `@Bindable` exposes `$store.scope(...)` projection used by
    /// `.sheet(item:)` for the Settings presentation. Other state
    /// reads happen via the regular `store.foo` accessors.
    @Bindable var store: StoreOf<HomeFeature>

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Dependency(\.calendarContext) private var calendarContext
    /// VisionKit's scanner is unavailable on Simulator and on Mac
    /// configurations without a paired camera. The Menu in HomeTopBar
    /// hides the Scan item when this returns false rather than
    /// surfacing a disabled affordance.
    @Dependency(\.documentScannerService) private var documentScannerService

    private let ds = DesignSystem.standard

    /// Days each side of "today" included in the wheel — matches the React
    /// design mock. Once the journal extent is queryable from SwiftData this
    /// will become `max(45, daysSinceEarliestBrief)`.
    private static let wheelRange = 45

    /// Local search text. Kept as `@State` here because the underlying
    /// reducer (HomeFeature.searchText) is read-only — the binding setter
    /// was a no-op which produced an unresponsive search field. When the
    /// search feature lands as a proper child reducer, this moves into
    /// state and the binding wires to a `searchTextChanged` action.
    @State private var localSearchText: String = ""

    /// **TEMPORARY — DELETE AFTER PoC VERIFICATION.** Drives the floating
    /// "Slash Editor PoC" button that presents `SlashEditorPoCView`.
    /// Used to verify the TextKit 1 + custom NSLayoutManager rendering
    /// approach before refactoring the production editor. Remove this
    /// state + the overlay below + SlashEditorPoC.swift once we've
    /// confirmed the approach renders block-level structure.
    @State private var showSlashEditorPoC = false

    private var filteredNotebooks: [NotebookSnapshot] {
        guard !localSearchText.isEmpty else { return store.library.notebooks }
        return store.library.notebooks.filter {
            $0.title.localizedCaseInsensitiveContains(localSearchText)
        }
    }

    private var rootNotebooks: [NotebookSnapshot] {
        filteredNotebooks.filter { $0.folderID == nil }
    }


    var body: some View {
        HomeScreenView(
            model: homeScreenModel,
            searchText: $localSearchText
        )
        .onAppear {
            store.send(.appeared)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.foregrounded` re-arms the time-advance timer + may
            // trigger a brief regen; `.backgrounded` tears the timer
            // down so we don't wake the device while suspended.
            // SwiftUI fires `.inactive` between active/background
            // transitions; treat it the same as background for timer
            // purposes (no point firing ticks during the interstitial).
            switch newPhase {
            case .active:                store.send(.foregrounded)
            case .background, .inactive: store.send(.backgrounded)
            @unknown default:            break
            }
        }
        .fullScreenCover(
            item: $store.scope(state: \.notebook, action: \.notebook)
        ) { notebookStore in
            NotebookScreen(store: notebookStore)
        }
        .fullScreenCover(
            item: $store.scope(state: \.libraryBrowse, action: \.libraryBrowse)
        ) { browseStore in
            LibraryBrowseView(
                store: browseStore,
                // Dismiss path clears the parent's @Presents optional.
                // `PresentationAction.dismiss` is the documented
                // primitive — fires the .ifLet's auto-clear, same as
                // SwiftUI's swipe-to-dismiss.
                chrome: LibraryBrowseView.Chrome(
                    onDismiss: { store.send(.libraryBrowse(.dismiss)) }
                )
            )
        }
        .fullScreenCover(
            item: $store.scope(state: \.pdfViewer, action: \.pdfViewer)
        ) { pdfStore in
            PDFViewerWiringView(store: pdfStore)
        }
        // Settings sheet driven by `@Presents`. `.sheet(item:)`
        // binds against the scoped optional store — non-nil presents,
        // nil dismisses, and SwiftUI's swipe-down gesture writes nil
        // back into the binding (which TCA routes through
        // `.settings(.dismiss)` automatically). Zero conditional
        // logic in the view.
        .sheet(item: $store.scope(state: \.settings, action: \.settings)) { settingsStore in
            SettingsWiringView(store: settingsStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(0)
                .presentationBackground(ds.colors.paper)
        }
        .overlay {
            if store.isNewNotebookSheetOpen {
                newNotebookOverlay
                    .transition(.opacity)
            }
        }
        // TEMPORARY — DELETE AFTER PoC VERIFICATION.
        .overlay(alignment: .topTrailing) {
            Button {
                showSlashEditorPoC = true
            } label: {
                Text("PoC")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red)
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        .fullScreenCover(isPresented: $showSlashEditorPoC) {
            SlashEditorPoCView()
        }
        .overlay {
            if let sheet = store.eventActionSheet {
                EventActionSheetView(model: eventActionSheetModel(for: sheet))
                    .transition(.opacity)
            }
        }
        .overlay {
            if let pickerStore = $store.scope(
                state: \.notebookPicker,
                action: \.notebookPicker
            ).wrappedValue {
                NotebookPickerWiringView(store: pickerStore)
                    .transition(.opacity)
            }
        }
        // Document acquisition mount — invisible. The choice between
        // file picker and scanner is handled by the Menu in HomeTopBar
        // (anchored natively to the doc icon on every platform).
        // Once a menu item is tapped, HomeFeature creates a
        // `DocumentImportFeature.State` with the appropriate initial
        // phase; this background slot mounts the wiring view, whose
        // `.fileImporter` / `.fullScreenCover` / `.alert` modifiers
        // activate based on phase.
        //
        // The `if let` form is the canonical TCA 1.10+ pattern for
        // optional-state child views (parallel to `.sheet(item:)` but
        // without imposing a sheet container).
        .background {
            if let importStore = $store.scope(
                state: \.documentImport,
                action: \.documentImport
            ).wrappedValue {
                DocumentImportWiringView(store: importStore)
            }
        }
        .alert(
            importAlertTitle,
            isPresented: Binding(
                get: { store.importAlert != nil },
                set: { newValue in
                    if !newValue { store.send(.importAlertDismissed) }
                }
            ),
            presenting: store.importAlert
        ) { alert in
            switch alert {
            case .duplicate:
                Button(AppStrings.Library.importPDFOpenButton) {
                    store.send(.importAlertOpenTapped)
                }
                Button(AppStrings.Common.cancel, role: .cancel) {
                    store.send(.importAlertDismissed)
                }
            case .failed:
                Button(AppStrings.Library.importPDFDismissButton, role: .cancel) {
                    store.send(.importAlertDismissed)
                }
            }
        } message: { alert in
            switch alert {
            case .duplicate(let snap):
                Text(AppStrings.Library.importPDFDuplicateMessage(title: snap.title))
            case .failed(let message):
                Text(message)
            }
        }
        .animation(ds.animation.standard, value: store.isNewNotebookSheetOpen)
        .animation(ds.animation.standard, value: store.isWheelOpen)
        .animation(ds.animation.standard, value: store.activeBriefTab)
        .animation(ds.animation.standard, value: store.dayContent)
    }

    /// Title for the import status alert, switched by case. The
    /// presented `alert` parameter on `.alert(_:isPresented:presenting:)`
    /// drives the body + actions; the title needs to resolve before the
    /// modifier sees the optional, so it derives from the current state.
    private var importAlertTitle: String {
        switch store.importAlert {
        case .duplicate:
            return AppStrings.Library.importPDFDuplicateTitle
        case .failed, .none:
            return AppStrings.Library.importPDFFailedTitle
        }
    }

    // MARK: - New Notebook Overlay

    @State private var newNotebookTitle = ""
    @State private var newNotebookType: NotebookType = .notebook

    private var newNotebookOverlay: some View {
        NewNotebookOverlay(
            title: $newNotebookTitle,
            type: $newNotebookType,
            onCreate: {
                // LibraryFeature creates via NotebookClient; its delegate
                // (.notebookCreated) is handled by HomeFeature, which
                // dismisses the sheet and sets presentingNotebookID.
                store.send(.library(.createNotebookRequested(
                    title: newNotebookTitle,
                    type: newNotebookType
                )))
                newNotebookTitle = ""
                newNotebookType = .notebook
            },
            onCancel: {
                store.send(.newNotebookDismissed)
                newNotebookTitle = ""
                newNotebookType = .notebook
            }
        )
    }

    // MARK: - Model Bridge

    private var homeScreenModel: HomeScreenView.Model {
        HomeScreenView.Model(
            topBar: topBarModel,
            // Focus mode collapses the entire daily-brief frame (large
            // date, lede, editor's note, and the calendar/reminders/
            // birthdays tab section). The shelves below stay visible
            // — focus mode is about removing the daily-brief framing,
            // not the user's notebooks.
            dailyBrief: store.isFocusMode ? nil : dailyBriefModel,
            shelf: shelfModel,
            notebooks: notebookCards,
            recentPDFs: recentPDFsModel,
            emptyState: rootNotebooks.isEmpty
                ? HomeEmptyState.Model(onCreateNotebook: { store.send(.newNotebookTapped) })
                : nil,
            nonFocalOpacity: store.isWheelOpen ? 0 : 1.0,
            nonFocalIsInteractive: !store.isWheelOpen,
            onScrimTap: store.isWheelOpen ? { store.send(.wheelToggled) } : nil
        )
    }

    /// Builds the Recent PDFs shelf model, or `nil` when the library is
    /// empty of PDFs (the shelf renders nothing rather than showing a
    /// header above zero cards). Tap handlers are a no-op placeholder
    /// today — Phase 3 (`PDFFeature` viewer) wires them to a presentation.
    private var recentPDFsModel: HomeRecentPDFsShelf.Model? {
        let pdfs = filteredPDFs
        guard !pdfs.isEmpty else { return nil }
        let cards = pdfs.map { snap in
            HomeRecentPDFsShelf.PDFCardModel(
                id: snap.id,
                title: snap.title,
                pagesLabel: "\(snap.pageCount) \(AppStrings.Home.pdfPagesLabel)",
                thumbnailData: snap.thumbnailData,
                onTap: { store.send(.pdfCardTapped(id: snap.id)) }
            )
        }
        return HomeRecentPDFsShelf.Model(pdfs: cards)
    }

    /// Applies the home search filter to the loaded recent-PDF
    /// snapshots. Cheap (small N) and consistent with how
    /// `filteredNotebooks` filters its source.
    private var filteredPDFs: [ImportedPDFSnapshot] {
        guard !localSearchText.isEmpty else { return store.library.recentPDFs }
        return store.library.recentPDFs.filter {
            $0.title.localizedCaseInsensitiveContains(localSearchText)
        }
    }

    private var topBarModel: HomeTopBar.Model {
        HomeTopBar.Model(
            onSettings: { store.send(.settingsTapped) },
            onFocusModeToggled: { store.send(.focusModeToggled) },
            isFocusMode: store.isFocusMode,
            onImportPDF: { store.send(.importPDFTapped) },
            onScanDocument: { store.send(.scanDocumentTapped) },
            onCompose: { store.send(.newNotebookTapped) },
            scanDocumentAvailable: documentScannerService.isAvailable()
        )
    }

    private var dailyBriefModel: HomeDailyBrief.Model {
        let snapshot: DailyBriefSnapshot
        switch store.briefState {
        case .loaded(let s):
            snapshot = s
        case .loading, .empty:
            snapshot = emptyBriefSnapshot
        }

        return HomeDailyBrief.Model(
            metaRow: BriefMetaRow.Model(
                syncLabel: syncLabel(for: snapshot.generatedAt),
                shortDate: shortDateLabel
            ),
            dateBlock: MastheadDateBlock.Model(
                weekday: store.currentDate.formatted(
                    .dateTime.weekday(.wide).locale(calendarContext.userLocale())
                ),
                monthDay: store.currentDate.formatted(
                    .dateTime.month(.wide).day().locale(calendarContext.userLocale())
                ),
                compact: horizontalSizeClass == .compact
            ),
            onDateTapped: { store.send(.wheelToggled) },
            timeWarpWheel: store.isWheelOpen ? buildTimeWarpWheel() : nil,
            mastheadPill: MastheadPill.Model(isExpanded: store.isWheelOpen),
            mastheadAccessibilityLabel: store.currentDate.formatted(
                .dateTime.weekday(.wide).month(.wide).day().year()
                    .locale(calendarContext.userLocale())
            ),
            mastheadAccessibilityHint: store.isWheelOpen
                ? AppStrings.Home.mastheadCloseHint
                : AppStrings.Home.mastheadOpenHint,
            backToTodayAction: store.isWarped ? {
                store.send(.dateWarpedTo(calendarContext.now()))
            } : nil,
            onDoneTapped: store.isWheelOpen ? { store.send(.wheelToggled) } : nil,
            onScrimTap: store.isWheelOpen ? { store.send(.wheelToggled) } : nil,
            onRefreshRequested: { store.send(.briefRefreshRequested) },
            lede: BriefLede.Model(
                text: firstSentence(of: snapshot.focusText)
            ),
            editorsNote: EditorsNoteSection.Model(
                paragraphs: editorsNoteParagraphs(snapshot: snapshot)
            ),
            tabSection: buildTabSection(),
            nonFocalOpacity: store.isWheelOpen ? 0 : 1.0,
            nonFocalIsInteractive: !store.isWheelOpen,
            isWheelMode: store.isWheelOpen
        )
    }

    // MARK: - Tab section

    /// Builds the tab strip + body from live EventKit (`dayContent`).
    /// Shows zeros for the ~1 frame after launch before `loadDayContent`
    /// resolves — no cached snapshot contribution since persisted counts
    /// are internal to `DailyBriefClient` (staleness checksum), not view data.
    private func buildTabSection() -> BriefTabSection.Model {
        let highlights: [StoredHighlight]
        let birthdays: [StoredBirthday]
        let eventCount: Int
        let reminderCount: Int
        let birthdayCount: Int

        if let content = store.dayContent {
            highlights = content.events + content.reminders
            birthdays = content.birthdays
            eventCount = content.eventCount
            reminderCount = content.reminderCount
            birthdayCount = content.birthdayCount
        } else {
            // First-frame fallback: dayContent hasn't resolved yet (the
            // ~1 frame after launch before `loadDayContent` completes).
            // Show zeros rather than fabricating counts — the live values
            // arrive within milliseconds.
            highlights = []
            birthdays = []
            eventCount = 0
            reminderCount = 0
            birthdayCount = 0
        }

        // Wheel mode forces the calendar tab on (reducer sets
        // activeBriefTab = .calendar on open). When the wheel is closed
        // and no tab is active, the panel is collapsed — `nil` keeps the
        // legacy behavior.
        let activeTab = store.activeBriefTab

        return BriefTabSection.Model(
            activeTab: activeTab,
            tabStrip: BriefTabStrip.Model(
                activeTab: activeTab,
                eventCount: eventCount,
                reminderCount: reminderCount,
                birthdayCount: birthdayCount,
                showsLabel: horizontalSizeClass != .compact,
                onTabTapped: { tab in store.send(.briefTabTapped(tab)) }
            ),
            events: eventRowModels(from: highlights),
            reminders: reminderRowModels(from: highlights),
            birthdays: birthdays.map(birthdayRow)
        )
    }

    /// Highlights with mealtime-ish `time` strings or "Next up" / "Upcoming"
    /// categories are treated as events. The richer event metadata
    /// (location, duration, isNext, notebook link) will arrive when the
    /// EventKit pipeline ships; for now, surface what's in the highlight.
    private func eventRowModels(from highlights: [StoredHighlight]) -> [BriefEventRow.Model] {
        // All-day events are already pinned ahead of timed events by
        // `buildHighlights`. Preserve that ordering here.
        //
        // Resolution of `isInProgress` + trailing badge is delegated
        // to `EventRowResolver` — a free-function namespace that's
        // unit-testable in isolation, in contrast to this private
        // adapter method which is buried inside a SwiftUI view.
        let now = store.nowTick
        let calendar = calendarContext.userCalendar()
        let linkLookup = store.eventLinkLookup
        return highlights
            .filter { $0.category == .allDay || $0.category == .upcoming }
            .enumerated()
            .map { index, h in
                let (isInProgress, badge) = EventRowResolver.resolve(
                    highlight: h,
                    now: now,
                    calendar: calendar
                )

                // Linked-notebook visual signal. The existing
                // `notebookLink` pill below the event title carries
                // the notebook title; pageLabel is left blank in V1
                // (page-level affordance comes with the page-resolver
                // PR). pageIndex is a layout placeholder; the actual
                // navigation uses `link.pageID` via HomeFeature.
                let link: CalendarItemLink.Snapshot? = {
                    guard let identifier = h.localIdentifier else { return nil }
                    return linkLookup[identifier]
                }()
                let notebookLink: BriefEventRow.Model.NotebookLink? = link.map { snap in
                    BriefEventRow.Model.NotebookLink(
                        notebookTitle: snap.notebookTitle,
                        pageLabel: "",
                        notebookID: snap.notebookID ?? UUID(),
                        pageIndex: 0
                    )
                }

                // Tap behavior: forward to `eventRowTapped` with the
                // identifier when one exists. Highlights with no EK
                // source (synthesized from notebook content, future)
                // get a no-op closure so the row still renders but
                // doesn't pretend to do anything on tap.
                let identifier = h.localIdentifier
                let tapHandler: () -> Void = {
                    guard let id = identifier else { return }
                    store.send(.eventRowTapped(identifier: id))
                }
                let hint = link == nil
                    ? AppStrings.EventActionSheet.unlinkedRowAccessibilityHint
                    : AppStrings.EventActionSheet.linkedRowAccessibilityHint

                return BriefEventRow.Model(
                    id: "event-\(index)",
                    time: h.time,
                    title: h.title,
                    location: nil,
                    duration: badge,
                    isInProgress: isInProgress,
                    notebookLink: notebookLink,
                    onTap: tapHandler,
                    accessibilityHint: identifier == nil ? "" : hint
                )
            }
    }

    private func reminderRowModels(from highlights: [StoredHighlight]) -> [BriefReminderRow.Model] {
        // Same pinning rule: `.anytime` reminders come first via
        // `buildHighlights`. `.anytime` reminders never read as overdue
        // or flagged — those signals require a clock time.
        let linkLookup = store.reminderLinkLookup
        return highlights
            .filter { $0.category == .anytime || $0.category == .overdue || $0.category == .today }
            .enumerated()
            .map { index, h in
                let link: CalendarItemLink.Snapshot? = {
                    guard let identifier = h.localIdentifier else { return nil }
                    return linkLookup[identifier]
                }()
                let notebookLink: BriefReminderRow.Model.NotebookLink? = link.map { snap in
                    BriefReminderRow.Model.NotebookLink(
                        notebookTitle: snap.notebookTitle,
                        notebookID: snap.notebookID ?? UUID()
                    )
                }
                let identifier = h.localIdentifier
                let tapHandler: () -> Void = {
                    guard let id = identifier else { return }
                    store.send(.reminderRowTapped(identifier: id))
                }
                let hint = link == nil
                    ? AppStrings.EventActionSheet.unlinkedRowAccessibilityHint
                    : AppStrings.EventActionSheet.linkedRowAccessibilityHint

                return BriefReminderRow.Model(
                    id: "reminder-\(index)",
                    title: h.title,
                    metaText: h.time,
                    listName: h.trailingBadge,
                    isFlagged: h.category == .overdue,
                    isOverdue: h.category == .overdue,
                    notebookLink: notebookLink,
                    onTap: tapHandler,
                    accessibilityHint: identifier == nil ? "" : hint
                )
            }
    }

    private func birthdayRow(_ b: StoredBirthday) -> BriefBirthdayRow.Model {
        BriefBirthdayRow.Model(
            id: b.id.uuidString,
            initials: b.initials,
            name: b.name,
            relationship: b.relationship,
            note: b.note,
            ageLabel: b.ageLabel
        )
    }


    private var shelfModel: HomeNotebookShelf.Model {
        HomeNotebookShelf.Model(
            notebooks: notebookCards,
            onViewAllTapped: { store.send(.libraryBrowseRequested) }
        )
    }

    private var notebookCards: [HomeNotebookShelf.NotebookCardModel] {
        rootNotebooks.map { snap in
            HomeNotebookShelf.NotebookCardModel(
                id: snap.id,
                title: snap.title,
                timeLabel: relativeTimeLabel(snap.modifiedAt),
                onTap: {
                    // HomeFeature.notebookTapped sets presentingNotebookID
                    // AND forwards .library(.touchNotebookActivated) so the
                    // shelf re-sorts on next refresh.
                    store.send(.notebookTapped(id: snap.id))
                }
            )
        }
    }

    // MARK: - Time Warp Wheel

    private func buildTimeWarpWheel() -> TimeWarpWheelScroller.Model {
        let today = calendarContext.now()
        let calendar = calendarContext.userCalendar()
        let dates = (-Self.wheelRange...Self.wheelRange).compactMap { offset in
            calendarContext.add(.day, offset, today)
        }
        let device: TimeWarpWheelView.Model.Device =
            horizontalSizeClass == .regular ? .iPad : .iPhone

        return TimeWarpWheelScroller.Model(
            device: device,
            dates: dates,
            selectedDate: store.currentDate,
            today: today,
            calendar: calendar,
            locale: calendarContext.userLocale(),
            timeZone: calendarContext.userTimeZone(),
            onDateSelected: { date in
                store.send(.dateWarpedTo(date))
            },
            onClose: { store.send(.wheelToggled) }
        )
    }

    // MARK: - Brief Helpers

    private var emptyBriefSnapshot: DailyBriefSnapshot {
        // Synthetic in-memory placeholder for the `.loading` / `.empty`
        // states — never written to SwiftData, so `wasPersisted: false`.
        DailyBriefSnapshot(
            dayKey: "",
            focusText: emptyBriefMessage,
            suggestionText: "",
            generatedAt: calendarContext.now(),
            wasPersisted: false
        )
    }

    /// Locale-aware empty message that distinguishes the warped case from
    /// today. When viewing today's empty state, the user is presumably
    /// looking at "today is quiet"; when warped, they're looking at a day
    /// that simply has no recorded brief.
    private var emptyBriefMessage: String {
        guard !calendarContext.isToday(store.currentDate) else {
            return AppStrings.Home.noEventsToday
        }
        let formatted = store.currentDate.formatted(
            .dateTime.weekday(.wide).month(.wide).day().year()
                .locale(calendarContext.userLocale())
        )
        return AppStrings.Home.noBriefForDate(formatted)
    }

    /// Compact "WED · 05/13/26"-style label rendered in the meta row.
    /// Always derived from the user's calendar context locale — uppercased
    /// via `uppercased(with:)` so language-specific casing rules apply
    /// (e.g., Turkish dotless-i, German ß handling).
    private var shortDateLabel: String {
        let d = store.currentDate
        let locale = calendarContext.userLocale()
        let weekday = d.formatted(.dateTime.weekday(.abbreviated).locale(locale))
            .uppercased(with: locale)
        let date = d.formatted(
            .dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits).locale(locale)
        )
        return "\(weekday) · \(date)"
    }

    /// Returns the editor's note paragraphs OR an empty array if FM
    /// produced nothing. Empty array signals the view layer to hide
    /// the section entirely — the tabs below still show events and
    /// reminders, which is the user-facing truth. See
    /// `localization_edd.md §5` (hide-rather-than-fake).
    private func editorsNoteParagraphs(snapshot: DailyBriefSnapshot) -> [String] {
        var paragraphs: [String] = []
        if !snapshot.focusText.isEmpty { paragraphs.append(snapshot.focusText) }
        if !snapshot.suggestionText.isEmpty { paragraphs.append(snapshot.suggestionText) }
        return paragraphs
    }

    private func syncLabel(for date: Date) -> String {
        AppStrings.Home.syncedRelative(relativeFormatter.localizedString(
            for: date,
            relativeTo: calendarContext.now()
        ))
    }

    /// Locale-aware "last touched" label — e.g. "5 minutes ago" / "il y a
    /// 5 minutes" / "٥ دقائق". Sub-minute durations collapse to the
    /// localized "Now" label to match the prior visual rhythm.
    private func relativeTimeLabel(_ date: Date) -> String {
        let seconds = abs(calendarContext.now().timeIntervalSince(date))
        if seconds < 60 { return AppStrings.Home.now }
        return relativeFormatter.localizedString(
            for: date,
            relativeTo: calendarContext.now()
        )
    }

    /// Lazily-built locale-aware formatter. `RelativeDateTimeFormatter` is
    /// expensive to construct (CLDR table lookup), so we cache one and rebuild
    /// only if the user's locale changes mid-render via `.autoupdatingCurrent`.
    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = calendarContext.userLocale()
        formatter.unitsStyle = .abbreviated
        return formatter
    }

    private func firstSentence(of text: String) -> String {
        guard let range = text.range(of: ".", options: .literal) else { return text }
        return String(text[text.startIndex...range.lowerBound])
    }

    // MARK: - Event action sheet

    private func eventActionSheetModel(
        for sheet: EventActionSheetState
    ) -> EventActionSheetView.Model {
        let ds = DesignSystem.standard
        let isLinked = sheet.linkedNotebook != nil
        return EventActionSheetView.Model(
            title: isLinked
                ? AppStrings.EventActionSheet.linkedTitle
                : AppStrings.EventActionSheet.unlinkedTitle,
            subtitle: sheet.hasRecurrenceRules
                ? AppStrings.EventActionSheet.recurringSeriesCopy
                : nil,
            actions: eventActionSheetActions(for: sheet, ds: ds),
            onDismiss: { store.send(.eventActionDismissed) },
            onScrimTap: { store.send(.eventActionDismissed) },
            dismissAccessibilityLabel: AppStrings.EventActionSheet.dismissAction,
            cardWidth: 360,
            cardBackground: ds.colors.paper,
            cardBorderColor: ds.colors.ink,
            cardBorderWidth: ds.layout.borderWidth,
            scrimColor: ds.colors.ink.opacity(ds.layout.scrimOpacity),
            titleFont: .system(size: 14, weight: .medium, design: .monospaced),
            titleColor: ds.colors.ink2,
            subtitleFont: .system(size: 12, weight: .regular, design: .serif),
            subtitleColor: ds.colors.ink3,
            subtitleHorizontalPadding: ds.spacing.lg,
            subtitleVerticalPadding: ds.spacing.sm,
            headerHorizontalPadding: ds.spacing.sm,
            headerHeight: ds.spacing.xxl,
            dismissIconSize: ds.layout.dismissIconSize,
            dismissFrame: ds.layout.dismissHitTarget,
            dismissIconColor: ds.colors.ink2
        )
    }

    private func eventActionSheetActions(
        for sheet: EventActionSheetState,
        ds: DesignSystem
    ) -> [EventActionSheetActionRow.Model] {
        let isReminder = sheet.kind == .reminder
        let openInSystemAppLabel = isReminder
            ? AppStrings.EventActionSheet.openInReminders
            : AppStrings.EventActionSheet.openInCalendar
        let openInSystemAppIcon = isReminder ? "checklist" : "calendar"

        if let linked = sheet.linkedNotebook {
            return [
                .init(
                    label: AppStrings.EventActionSheet.openLinkedNotebook(linked.notebookTitle),
                    iconSystemName: "book.closed.fill",
                    onTap: { store.send(.eventActionOpenLinkedNotebookTapped) },
                    ds: ds
                ),
                .init(
                    label: openInSystemAppLabel,
                    iconSystemName: openInSystemAppIcon,
                    onTap: { store.send(.eventActionOpenInCalendarTapped) },
                    ds: ds
                )
            ]
        }
        let createLabel = isReminder
            ? AppStrings.EventActionSheet.createNotebookFromReminder
            : AppStrings.EventActionSheet.createNotebookFromEvent
        return [
            .init(
                label: createLabel,
                iconSystemName: "plus.rectangle.on.rectangle",
                onTap: { store.send(.eventActionCreateTapped) },
                ds: ds
            ),
            .init(
                label: AppStrings.EventActionSheet.linkToExistingNotebook,
                iconSystemName: "link",
                onTap: { store.send(.eventActionLinkTapped) },
                ds: ds
            ),
            .init(
                label: openInSystemAppLabel,
                iconSystemName: openInSystemAppIcon,
                onTap: { store.send(.eventActionOpenInCalendarTapped) },
                ds: ds
            )
        ]
    }
}
