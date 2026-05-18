import SwiftUI
import SwiftData

/// Feature view that bridges real data into the stateless home screen.
///
/// Brief lifecycle is owned by BootstrapFeature (seed) and will move
/// to a HomeFeature reducer (calendar refresh). This view receives
/// the brief snapshot as input — no @Dependency access.
///
struct HomeFeatureView: View {
    var initialBrief: DailyBriefSnapshot?

    @Query(sort: \Notebook.lastOpenedAt, order: .reverse) private var notebooks: [Notebook]
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @Environment(\.modelContext) private var modelContext
    private let ds = DesignSystem.standard

    @State private var briefSnapshot: DailyBriefSnapshot?
    @State private var searchText = ""
    @State private var isBriefExpanded = false
    @State private var activeNotebook: Notebook? = nil
    @State private var showNewNotebookSheet = false
    @State private var showSettings = false
    @State private var newNotebookTitle = ""

    private var filteredNotebooks: [Notebook] {
        guard !searchText.isEmpty else { return notebooks }
        return notebooks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var rootNotebooks: [Notebook] {
        filteredNotebooks.filter { $0.folderID == nil }
    }

    var body: some View {
        HomeScreenView(
            model: homeScreenModel,
            searchText: $searchText,
            isBriefExpanded: $isBriefExpanded
        )
        .onAppear {
            briefSnapshot = initialBrief
            seedNotebookIfNeeded()
        }
        .onChange(of: initialBrief) { _, newBrief in
            briefSnapshot = newBrief
        }
        .fullScreenCover(item: $activeNotebook) { notebook in
            NotebookScreen(notebookID: notebook.id, notebookTitle: notebook.title)
        }
        .overlay {
            if showSettings {
                SettingsScreen(onDismiss: { showSettings = false })
                    .transition(.opacity)
            }
        }
        .animation(ds.animation.standard, value: showSettings)
        .overlay {
            if showNewNotebookSheet {
                NewNotebookOverlay(
                    title: $newNotebookTitle,
                    onCreate: {
                        let notebook = Notebook(
                            title: newNotebookTitle.isEmpty
                                ? AppStrings.Common.untitled
                                : newNotebookTitle
                        )
                        modelContext.insert(notebook)
                        try? modelContext.save()
                        showNewNotebookSheet = false
                        activeNotebook = notebook
                    },
                    onCancel: { showNewNotebookSheet = false }
                )
                .transition(.opacity)
            }
        }
        .animation(ds.animation.standard, value: showNewNotebookSheet)
    }

    // MARK: - Model Bridge

    private var homeScreenModel: HomeScreenView.Model {
        HomeScreenView.Model(
            topBar: topBarModel,
            dailyBrief: dailyBriefModel,
            shelf: shelfModel,
            notebooks: notebookCards
        )
    }

    private var topBarModel: HomeTopBar.Model {
        HomeTopBar.Model(
            onSettings: { showSettings = true },
            onCompose: {
                newNotebookTitle = ""
                showNewNotebookSheet = true
            }
        )
    }

    private var dailyBriefModel: HomeDailyBrief.Model {
        let snapshot = briefSnapshot ?? emptyBriefSnapshot

        return HomeDailyBrief.Model(
            metaRow: BriefMetaRow.Model(
                syncLabel: syncLabel(for: snapshot.generatedAt),
                shortDate: shortDateLabel
            ),
            dateBlock: MastheadDateBlock.Model(
                weekday: Date().formatted(.dateTime.weekday(.wide)),
                monthDay: Date().formatted(.dateTime.month(.wide).day())
            ),
            // Legacy entry point — wheel not wired here. The TCA-based
            // HomeWiringView is the canonical home view.
            onDateTapped: { },
            timeWarpWheel: nil,
            lede: BriefLede.Model(
                text: firstSentence(of: snapshot.focusText)
            ),
            countsBar: BriefCountsBar.Model(
                eventCount: snapshot.eventCount,
                reminderCount: snapshot.reminderCount,
                isExpanded: isBriefExpanded,
                onToggle: {
                    withAnimation(ds.animation.standard) {
                        isBriefExpanded.toggle()
                    }
                }
            ),
            editorsNote: EditorsNoteSection.Model(
                paragraphs: editorsNoteParagraphs(snapshot: snapshot)
            ),
            highlights: highlightRows(snapshot: snapshot),
            footerActions: BriefFooterActions.Model(
                onViewDetails: { },
                onCollapse: {
                    withAnimation(ds.animation.standard) {
                        isBriefExpanded = false
                    }
                }
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
                    activeNotebook = notebook
                }
            )
        }
    }

    // MARK: - Brief Helpers

    private var shortDateLabel: String {
        let d = Date()
        let weekday = d.formatted(
            .dateTime.weekday(.abbreviated)
        ).uppercased()
        let date = d.formatted(
            .dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits)
        )
        return "\(weekday) · \(date)"
    }

    private func editorsNoteParagraphs(
        snapshot: DailyBriefSnapshot
    ) -> [String] {
        var paragraphs: [String] = []
        if !snapshot.focusText.isEmpty {
            paragraphs.append(snapshot.focusText)
        }
        if !snapshot.suggestionText.isEmpty {
            paragraphs.append(snapshot.suggestionText)
        }
        if paragraphs.isEmpty {
            paragraphs = ["No events or reminders today."]
        }
        return paragraphs
    }

    private func highlightRows(
        snapshot: DailyBriefSnapshot
    ) -> [HighlightRow.Model] {
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
        if seconds < 60 { return "Now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return "\(days) d"
    }

    private func firstSentence(of text: String) -> String {
        guard let range = text.range(of: ".", options: .literal) else {
            return text
        }
        return String(text[text.startIndex...range.lowerBound])
    }

    private var emptyBriefSnapshot: DailyBriefSnapshot {
        DailyBriefSnapshot(
            dayKey: "",
            focusText: "No events or reminders today. A clear day for deep work.",
            suggestionText: "",
            eventCount: 0,
            reminderCount: 0,
            generatedAt: Date(),
            highlights: []
        )
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
