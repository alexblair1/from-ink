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
            if newPhase == .active {
                store.send(.foregrounded)
            }
        }
        .fullScreenCover(
            item: $store.scope(state: \.notebook, action: \.notebook)
        ) { notebookStore in
            NotebookScreen(store: notebookStore)
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
        .fileImporter(
            isPresented: Binding(
                get: { store.isImportPickerOpen },
                set: { newValue in
                    // The view only ever sets this to false (user
                    // cancellation / SwiftUI dismissing the sheet).
                    // The reducer opens it via .importPDFTapped.
                    if !newValue {
                        store.send(.importPickerDismissed)
                    }
                }
            ),
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                store.send(.importPDFPicked(url))
            case .failure:
                // SwiftUI surfaces its own picker error; we just clear
                // the open state so the binding stays consistent.
                store.send(.importPickerDismissed)
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
        ) { _ in
            // Single OK action across all three cases; Phase 3 splits
            // duplicate/imported into a viewer-presentation path with
            // a second "Open" button.
            Button(AppStrings.Library.importPDFDismissButton, role: .cancel) {
                store.send(.importAlertDismissed)
            }
        } message: { alert in
            switch alert {
            case .duplicate(let snap):
                Text(AppStrings.Library.importPDFDuplicateMessage(title: snap.title))
            case .failed(let message):
                Text(message)
            case .imported(let snap):
                Text(AppStrings.Library.importPDFSuccessMessage(title: snap.title))
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
        case .imported:
            return AppStrings.Library.importPDFSuccessTitle
        case .failed, .none:
            return AppStrings.Library.importPDFFailedTitle
        }
    }

    // MARK: - New Notebook Overlay

    @State private var newNotebookTitle = ""

    private var newNotebookOverlay: some View {
        NewNotebookOverlay(
            title: $newNotebookTitle,
            onCreate: {
                // LibraryFeature creates via NotebookClient; its delegate
                // (.notebookCreated) is handled by HomeFeature, which
                // dismisses the sheet and sets presentingNotebookID.
                store.send(.library(.createNotebookRequested(title: newNotebookTitle)))
                newNotebookTitle = ""
            },
            onCancel: {
                store.send(.newNotebookDismissed)
                newNotebookTitle = ""
            }
        )
    }

    // MARK: - Model Bridge

    private var homeScreenModel: HomeScreenView.Model {
        HomeScreenView.Model(
            topBar: topBarModel,
            dailyBrief: dailyBriefModel,
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
                onTap: { /* Phase 3: present PDFFeature for snap.id */ }
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
            onImportPDF: { store.send(.importPDFTapped) },
            onCompose: { store.send(.newNotebookTapped) }
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
        // `buildHighlights`. Preserve that ordering here — the upstream
        // sort is the source of truth, not the index-based isNext check.
        highlights
            .filter { $0.category == .allDay || $0.category == .nextUp || $0.category == .upcoming }
            .enumerated()
            .map { index, h in
                BriefEventRow.Model(
                    id: "event-\(index)",
                    time: h.time,
                    title: h.title,
                    location: nil,
                    duration: h.trailingBadge,
                    isNext: h.category == .nextUp,
                    nextPillLabel: HighlightCategory.nextUp.displayString,
                    notebookLink: nil
                )
            }
    }

    private func reminderRowModels(from highlights: [StoredHighlight]) -> [BriefReminderRow.Model] {
        // Same pinning rule: `.anytime` reminders come first via
        // `buildHighlights`. `.anytime` reminders never read as overdue
        // or flagged — those signals require a clock time.
        highlights
            .filter { $0.category == .anytime || $0.category == .overdue || $0.category == .today }
            .enumerated()
            .map { index, h in
                BriefReminderRow.Model(
                    id: "reminder-\(index)",
                    title: h.title,
                    metaText: h.time,
                    listName: h.trailingBadge,
                    isFlagged: h.category == .overdue,
                    isOverdue: h.category == .overdue
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
        HomeNotebookShelf.Model(notebooks: notebookCards)
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
}
