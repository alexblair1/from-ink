import SwiftUI
import SwiftData
import ComposableArchitecture

/// Feature view that bridges real data into the stateless `HomeScreen`.
///
/// Owns:
///   - `DailyBriefFeature` TCA store (weather, events, reminders, AI brief)
///   - SwiftData queries for `Notebook` and `Folder`
///   - Navigation state (active notebook, new-notebook sheet)
///
/// Delegates all rendering to `HomeScreen` via its `Model`.
///
struct HomeFeatureView: View {
    @Query(sort: \Notebook.lastOpenedAt, order: .reverse) private var notebooks: [Notebook]
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @Environment(\.modelContext) private var modelContext
    private let ds = DesignSystem.standard

    @State private var briefStore = Store(initialState: DailyBriefFeature.State()) {
        DailyBriefFeature()
    }
    @State private var searchText = ""
    @State private var activeNotebook: Notebook? = nil
    @State private var showNewNotebookSheet = false
    @State private var showSettings = false
    @State private var newNotebookTitle = ""

    private var filteredNotebooks: [Notebook] {
        guard !searchText.isEmpty else { return notebooks }
        return notebooks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var rootNotebooks: [Notebook] {
        filteredNotebooks.filter { $0.folderID == nil }
    }

    var body: some View {
        HomeScreen(model: homeModel)
            .onAppear {
                briefStore.send(.appeared)
                seedNotebookIfNeeded()
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
                                title: newNotebookTitle.isEmpty ? AppStrings.Common.untitled : newNotebookTitle
                            )
                            modelContext.insert(notebook)
                            try? modelContext.save()
                            showNewNotebookSheet = false
                            activeNotebook = notebook
                        },
                        onCancel: {
                            showNewNotebookSheet = false
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(ds.animation.standard, value: showNewNotebookSheet)
    }

    // MARK: - Model bridge

    private var homeModel: HomeScreen.Model {
        HomeScreen.Model(
            masthead: mastheadModel,
            searchText: $searchText,
            onSearchChanged: { searchText = $0 },
            folders: folders.map { folder in
                HomeScreen.Model.FolderItem(
                    id: folder.id,
                    name: folder.name,
                    notebookCount: notebooks.filter { $0.folderID == folder.id }.count,
                    icon: "folder"
                )
            },
            notebooks: rootNotebooks.map { notebook in
                HomeScreen.Model.NotebookItem(
                    id: notebook.id,
                    title: notebook.title,
                    subtitle: notebook.lastOpenedAt.formatted(.relative(presentation: .named)),
                    coverColor: coverColor(for: notebook)
                )
            },
            onFolder: { _ in /* folder navigation — not yet wired */ },
            onNotebook: { id in
                if let notebook = notebooks.first(where: { $0.id == id }) {
                    notebook.lastOpenedAt = Date()
                    try? modelContext.save()
                    activeNotebook = notebook
                }
            },
            onNewNotebook: {
                newNotebookTitle = ""
                showNewNotebookSheet = true
            },
            onSettings: { showSettings = true }
        )
    }

    private var mastheadModel: HomeMasthead.Model {
        let state = briefStore.withState { $0 }

        return HomeMasthead.Model(
            weekday: Date().formatted(.dateTime.weekday(.wide)),
            monthDay: Date().formatted(.dateTime.month(.wide).day()),
            syncLabel: syncLabel(for: state.lastRefreshed),
            briefSentence: briefSentence(state: state),
            eventCount: state.events.count,
            reminderCount: state.reminders.count,
            birthdayCount: 0,
            weather: state.weather.map { weather in
                HomeMasthead.Model.WeatherInfo(
                    symbolName: weather.symbolName,
                    transitionSymbol: nil,
                    temperature: weather.formattedTemperature,
                    sunrise: nil,
                    sunset: nil
                )
            },
            expandedBrief: expandedBriefModel(state: state),
            onViewDetails: { }
        )
    }

    // MARK: - Brief helpers

    /// The masthead shows only the first sentence — a concise headline.
    /// The full multi-sentence focus lives in the expanded editor's note.
    private func briefSentence(state: DailyBriefFeature.State) -> String {
        if let focus = state.brief?.focus, !focus.isEmpty {
            return firstSentence(of: focus)
        }
        return firstSentence(of: narrativeFallback(events: state.events, reminders: state.reminders))
    }

    private func expandedBriefModel(state: DailyBriefFeature.State) -> HomeExpandedBrief.Model {
        var paragraphs: [String] = []
        if let brief = state.brief {
            if !brief.focus.isEmpty { paragraphs.append(brief.focus) }
            if !brief.suggestion.isEmpty { paragraphs.append(brief.suggestion) }
        }
        if paragraphs.isEmpty {
            paragraphs = [narrativeFallback(events: state.events, reminders: state.reminders)]
        }

        var highlights: [HomeExpandedBrief.Model.Highlight] = []

        // Next 3 upcoming events
        let now = Date()
        let upcomingEvents = state.events.filter { $0.startDate >= now || $0.endDate >= now }
        for (index, event) in upcomingEvents.prefix(3).enumerated() {
            let label = index == 0 ? AppStrings.Home.nextUp : AppStrings.Home.upcoming
            highlights.append(.init(
                icon: "calendar",
                label: label,
                text: "\(event.title) · \(event.startDate.formatted(.dateTime.hour().minute()))"
            ))
        }

        // Up to 3 due/overdue reminders
        for reminder in state.reminders.prefix(3) {
            let dueLabel = reminder.dueDate.map {
                $0 < now ? AppStrings.Home.overdue : AppStrings.Home.today
            } ?? AppStrings.Home.today
            highlights.append(.init(
                icon: "checklist",
                label: dueLabel,
                text: reminder.title
            ))
        }

        return HomeExpandedBrief.Model(
            paragraphs: paragraphs,
            highlights: highlights,
            onViewDetails: { },
            onCollapse: { }
        )
    }

    private func syncLabel(for date: Date?) -> String {
        guard let date else { return "loading" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "synced just now" }
        let minutes = seconds / 60
        return "synced \(minutes)m ago"
    }

    private func narrativeFallback(
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot]
    ) -> String {
        guard !events.isEmpty || !reminders.isEmpty else {
            return "No events or reminders today. A clear day for deep work."
        }
        var parts: [String] = []
        switch events.count {
        case 0: parts.append("No events scheduled today.")
        case 1: parts.append("You have \(events[0].title) at \(events[0].startDate.formatted(.dateTime.hour().minute())) today.")
        default:
            let listed = events.prefix(3).map { "\($0.title) at \($0.startDate.formatted(.dateTime.hour().minute()))" }
            let tail = events.count > 3 ? " and \(events.count - 3) more" : ""
            parts.append("Today: \(listed.joined(separator: ", "))\(tail).")
        }
        if !reminders.isEmpty {
            parts.append("\(reminders.count) reminder\(reminders.count == 1 ? "" : "s") due.")
        }
        return parts.joined(separator: " ")
    }

    private func firstSentence(of text: String) -> String {
        guard let range = text.range(of: ".", options: .literal) else { return text }
        let sentence = String(text[text.startIndex...range.lowerBound])
        return sentence
    }

    private func coverColor(for notebook: Notebook) -> Color {
        Color(hex: notebook.coverColorHex) ?? ColorTokens.standard.ink
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
