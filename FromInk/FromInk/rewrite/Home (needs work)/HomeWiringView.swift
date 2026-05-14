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

    private let ds = DesignSystem.standard

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
            ),
            isBriefExpanded: Binding(
                get: { store.isBriefExpanded },
                set: { _ in store.send(.toggleBriefExpanded) }
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
                : nil
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
                monthDay: store.currentDate.formatted(.dateTime.month(.wide).day())
            ),
            lede: BriefLede.Model(
                text: firstSentence(of: snapshot.focusText)
            ),
            countsBar: BriefCountsBar.Model(
                eventCount: snapshot.eventCount,
                reminderCount: snapshot.reminderCount,
                isExpanded: store.isBriefExpanded,
                onToggle: { store.send(.toggleBriefExpanded) }
            ),
            editorsNote: EditorsNoteSection.Model(
                paragraphs: editorsNoteParagraphs(snapshot: snapshot)
            ),
            highlights: highlightRows(snapshot: snapshot),
            footerActions: BriefFooterActions.Model(
                onViewDetails: { },
                onCollapse: { store.send(.toggleBriefExpanded) }
            )
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
                    notebook.lastOpenedAt = Date()
                    try? modelContext.save()
                    store.send(.notebookTapped(id: notebook.id))
                    activeNotebook = notebook
                }
            )
        }
    }

    // MARK: - Brief Helpers

    private var emptyBriefSnapshot: DailyBriefSnapshot {
        DailyBriefSnapshot(
            dayKey: "",
            focusText: AppStrings.Home.noEventsToday,
            suggestionText: "",
            eventCount: 0,
            reminderCount: 0,
            generatedAt: Date(),
            highlights: []
        )
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

    private func highlightRows(snapshot: DailyBriefSnapshot) -> [HighlightRow.Model] {
        snapshot.highlights.enumerated().map { index, highlight in
            HighlightRow.Model(
                id: "highlight-\(index)",
                category: highlight.category,
                icon: highlight.icon,
                title: highlight.title,
                time: highlight.time,
                trailingBadge: highlight.trailingBadge
            )
        }
    }

    private func syncLabel(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(AppStrings.Home.synced) \(AppStrings.Home.justNow)"
        }
        let minutes = seconds / 60
        return "\(AppStrings.Home.synced.lowercased()) \(minutes)m ago"
    }

    private func relativeTimeLabel(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return AppStrings.Home.now }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return "\(days) d"
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
