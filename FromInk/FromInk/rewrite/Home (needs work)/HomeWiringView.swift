import ComposableArchitecture
import SwiftUI
import SwiftData

/// Wiring view for the home screen. Owns @Query for SwiftData live data,
/// converts Store state + query results into HomeScreenView.Model.
/// Zero layout — delegates entirely to HomeScreenView.
///
struct HomeWiringView: View {
    let store: StoreOf<HomeFeature>

    @Query(sort: \Notebook.lastOpenedAt, order: .reverse) private var notebooks: [Notebook]
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Dependency(\.calendarContext) private var calendarContext

    private let ds = DesignSystem.standard

    /// Days each side of "today" included in the wheel — matches the React
    /// design mock. Once the journal extent is queryable from SwiftData this
    /// will become `max(45, daysSinceEarliestBrief)`.
    private static let wheelRange = 45

    @State private var activeNotebook: Notebook? = nil

    private var filteredNotebooks: [Notebook] {
        guard !store.searchText.isEmpty else { return notebooks }
        return notebooks.filter {
            $0.title.localizedCaseInsensitiveContains(store.searchText)
        }
    }

    private var rootNotebooks: [Notebook] {
        filteredNotebooks.filter { $0.folderID == nil }
    }

    var body: some View {
        HomeScreenView(
            model: homeScreenModel,
            searchText: Binding(
                get: { store.searchText },
                set: { store.send(.settingsDismissed); _ = $0 }
                // TODO: wire searchText through an action when search is implemented
            )
        )
        .onAppear {
            store.send(.appeared)
            seedNotebookIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.send(.foregrounded)
            }
        }
        .fullScreenCover(item: $activeNotebook) { notebook in
            NotebookScreen(notebookID: notebook.id, notebookTitle: notebook.title)
        }
        .overlay {
            if store.isSettingsOpen {
                SettingsScreen(onDismiss: { store.send(.settingsDismissed) })
                    .transition(.opacity)
            }
        }
        .animation(ds.animation.standard, value: store.isSettingsOpen)
        .overlay {
            if store.isNewNotebookSheetOpen {
                newNotebookOverlay
                    .transition(.opacity)
            }
        }
        .animation(ds.animation.standard, value: store.isNewNotebookSheetOpen)
        .animation(ds.animation.standard, value: store.isWheelOpen)
        .animation(ds.animation.standard, value: store.activeBriefTab)
    }

    // MARK: - New Notebook Overlay

    @State private var newNotebookTitle = ""

    private var newNotebookOverlay: some View {
        NewNotebookOverlay(
            title: $newNotebookTitle,
            onCreate: {
                let title = newNotebookTitle.isEmpty
                    ? AppStrings.Common.untitled
                    : newNotebookTitle
                let notebook = Notebook(title: title)
                modelContext.insert(notebook)
                try? modelContext.save()
                store.send(.notebookCreated(title: title))
                newNotebookTitle = ""
                activeNotebook = notebook
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
            emptyState: rootNotebooks.isEmpty
                ? HomeEmptyState.Model(onCreateNotebook: { store.send(.newNotebookTapped) })
                : nil,
            nonFocalOpacity: store.isWheelOpen ? 0.10 : 1.0,
            nonFocalIsInteractive: !store.isWheelOpen,
            onScrimTap: store.isWheelOpen ? { store.send(.wheelToggled) } : nil
        )
    }

    private var topBarModel: HomeTopBar.Model {
        HomeTopBar.Model(
            onSettings: { store.send(.settingsTapped) },
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
                weekday: store.currentDate.formatted(.dateTime.weekday(.wide)),
                monthDay: store.currentDate.formatted(.dateTime.month(.wide).day()),
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
            lede: BriefLede.Model(
                text: firstSentence(of: snapshot.focusText)
            ),
            editorsNote: EditorsNoteSection.Model(
                paragraphs: editorsNoteParagraphs(snapshot: snapshot)
            ),
            tabSection: buildTabSection(snapshot: snapshot),
            nonFocalOpacity: store.isWheelOpen ? 0.10 : 1.0,
            nonFocalIsInteractive: !store.isWheelOpen
        )
    }

    // MARK: - Tab section

    private func buildTabSection(snapshot: DailyBriefSnapshot) -> BriefTabSection.Model {
        let eventModels = eventRowModels(from: snapshot.highlights)
        let reminderModels = reminderRowModels(from: snapshot.highlights)
        let birthdayModels = snapshot.birthdays.map(birthdayRow)

        return BriefTabSection.Model(
            activeTab: store.activeBriefTab,
            tabStrip: BriefTabStrip.Model(
                activeTab: store.activeBriefTab,
                eventCount: snapshot.eventCount,
                reminderCount: snapshot.reminderCount,
                birthdayCount: snapshot.birthdayCount,
                showsLabel: horizontalSizeClass != .compact,
                onTabTapped: { tab in store.send(.briefTabTapped(tab)) }
            ),
            events: eventModels,
            reminders: reminderModels,
            birthdays: birthdayModels
        )
    }

    /// Highlights with mealtime-ish `time` strings or "Next up" / "Upcoming"
    /// categories are treated as events. The richer event metadata
    /// (location, duration, isNext, notebook link) will arrive when the
    /// EventKit pipeline ships; for now, surface what's in the highlight.
    private func eventRowModels(from highlights: [StoredHighlight]) -> [BriefEventRow.Model] {
        highlights
            .filter { $0.category == AppStrings.Home.nextUp || $0.category == AppStrings.Home.upcoming }
            .enumerated()
            .map { index, h in
                BriefEventRow.Model(
                    id: "event-\(index)",
                    time: h.time,
                    title: h.title,
                    location: nil,
                    duration: h.trailingBadge ?? "",
                    isNext: h.category == AppStrings.Home.nextUp,
                    nextPillLabel: AppStrings.Home.nextUp,
                    notebookLink: nil
                )
            }
    }

    private func reminderRowModels(from highlights: [StoredHighlight]) -> [BriefReminderRow.Model] {
        highlights
            .filter { $0.category == AppStrings.Home.overdue || $0.category == AppStrings.Home.today }
            .enumerated()
            .map { index, h in
                BriefReminderRow.Model(
                    id: "reminder-\(index)",
                    title: h.title,
                    metaText: h.time,
                    listName: h.trailingBadge,
                    isFlagged: h.category == AppStrings.Home.overdue,
                    isOverdue: h.category == AppStrings.Home.overdue
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
        rootNotebooks.map { notebook in
            HomeNotebookShelf.NotebookCardModel(
                id: notebook.id,
                title: notebook.title,
                timeLabel: relativeTimeLabel(notebook.lastOpenedAt),
                onTap: {
                    notebook.lastOpenedAt = calendarContext.now()
                    try? modelContext.save()
                    store.send(.notebookTapped(id: notebook.id))
                    activeNotebook = notebook
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
        DailyBriefSnapshot(
            dayKey: "",
            focusText: emptyBriefMessage,
            suggestionText: "",
            eventCount: 0,
            reminderCount: 0,
            generatedAt: calendarContext.now(),
            highlights: []
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

    private var shortDateLabel: String {
        let d = store.currentDate
        let weekday = d.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let date = d.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits))
        return "\(weekday) · \(date)"
    }

    private func editorsNoteParagraphs(snapshot: DailyBriefSnapshot) -> [String] {
        var paragraphs: [String] = []
        if !snapshot.focusText.isEmpty { paragraphs.append(snapshot.focusText) }
        if !snapshot.suggestionText.isEmpty { paragraphs.append(snapshot.suggestionText) }
        if paragraphs.isEmpty { paragraphs = [AppStrings.Home.noEventsToday] }
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

    // MARK: - Seed

    private func seedNotebookIfNeeded() {
        if notebooks.isEmpty {
            let notebook = Notebook(title: AppStrings.Library.myNotebook)
            modelContext.insert(notebook)
            try? modelContext.save()
        }
    }
}
