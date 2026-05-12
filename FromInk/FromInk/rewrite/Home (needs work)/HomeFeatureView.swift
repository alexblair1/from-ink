import SwiftUI
import SwiftData
import ComposableArchitecture

/// Feature view that bridges real data into the stateless home screen.
///
/// Owns:
///   - `DailyBriefFeature` TCA store (weather, events, reminders, AI brief)
///   - SwiftData queries for `Notebook` and `Folder`
///   - Navigation state (active notebook, new-notebook sheet)
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
        let state = briefStore.withState { $0 }

        return HomeDailyBrief.Model(
            metaRow: BriefMetaRow.Model(
                syncLabel: syncLabel(for: state.lastRefreshed),
                shortDate: shortDateLabel
            ),
            dateBlock: MastheadDateBlock.Model(
                weekday: Date().formatted(.dateTime.weekday(.wide)),
                monthDay: Date().formatted(.dateTime.month(.wide).day())
            ),
            lede: BriefLede.Model(
                text: briefSentence(state: state)
            ),
            countsBar: BriefCountsBar.Model(
                eventCount: state.events.count,
                reminderCount: state.reminders.count,
                isExpanded: isBriefExpanded,
                onToggle: {
                    withAnimation(ds.animation.standard) {
                        isBriefExpanded.toggle()
                    }
                }
            ),
            editorsNote: EditorsNoteSection.Model(
                paragraphs: editorsNoteParagraphs(state: state)
            ),
            highlights: highlightRows(state: state),
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
        let weekday = d.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let date = d.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits))
        return "\(weekday) · \(date)"
    }

    private func briefSentence(state: DailyBriefFeature.State) -> String {
        if let focus = state.brief?.focus, !focus.isEmpty {
            return firstSentence(of: focus)
        }
        return firstSentence(of: narrativeFallback(
            events: state.events,
            reminders: state.reminders
        ))
    }

    private func editorsNoteParagraphs(state: DailyBriefFeature.State) -> [String] {
        var paragraphs: [String] = []
        if let brief = state.brief {
            if !brief.focus.isEmpty { paragraphs.append(brief.focus) }
            if !brief.suggestion.isEmpty { paragraphs.append(brief.suggestion) }
        }
        if paragraphs.isEmpty {
            paragraphs = [narrativeFallback(
                events: state.events,
                reminders: state.reminders
            )]
        }
        return paragraphs
    }

    private func highlightRows(
        state: DailyBriefFeature.State
    ) -> [HighlightRow.Model] {
        var rows: [HighlightRow.Model] = []
        let now = Date()

        let upcomingEvents = state.events.filter {
            $0.startDate >= now || $0.endDate >= now
        }
        for (index, event) in upcomingEvents.prefix(3).enumerated() {
            let category = index == 0
                ? AppStrings.Home.nextUp
                : AppStrings.Home.upcoming
            let badge = eventBadge(event, now: now)
            rows.append(
                HighlightRow.Model(
                    id: "event-\(index)",
                    category: category,
                    icon: "calendar",
                    title: event.title,
                    time: event.startDate.formatted(
                        .dateTime.hour().minute()
                    ),
                    trailingBadge: badge
                )
            )
        }

        for (index, reminder) in state.reminders.prefix(3).enumerated() {
            let category = reminder.dueDate.map {
                $0 < now ? AppStrings.Home.overdue : AppStrings.Home.today
            } ?? AppStrings.Home.today
            let badge = reminder.dueDate.map { reminderBadge($0, now: now) } ?? ""
            rows.append(
                HighlightRow.Model(
                    id: "reminder-\(index)",
                    category: category,
                    icon: "clock",
                    title: reminder.title,
                    time: reminder.dueDate?.formatted(
                        .dateTime.hour().minute()
                    ) ?? "",
                    trailingBadge: badge
                )
            )
        }

        return rows
    }

    private func syncLabel(for date: Date?) -> String {
        guard let date else { return "loading" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(AppStrings.Home.synced) \(AppStrings.Home.justNow)" }
        let minutes = seconds / 60
        return "\(AppStrings.Home.synced.lowercased()) \(minutes)m ago"
    }

    private func eventBadge(
        _ event: CalendarEventSnapshot,
        now: Date
    ) -> String {
        let calendar = Calendar.current
        if calendar.isDate(event.startDate, inSameDayAs: now)
            && calendar.isDate(event.endDate, inSameDayAs: now)
            && calendar.dateComponents(
                [.hour], from: event.startDate, to: event.endDate
            ).hour ?? 0 >= 23 {
            return "All day"
        }
        let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "Now" }
        if minutes < 60 { return "In \(minutes) m" }
        let hours = minutes / 60
        return "In \(hours) h"
    }

    private func reminderBadge(_ dueDate: Date, now: Date) -> String {
        let minutes = Int(dueDate.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "Overdue" }
        if minutes < 60 { return "In \(minutes) m" }
        let hours = minutes / 60
        if hours < 24 { return "In \(hours) h" }
        let days = hours / 24
        return "In \(days) d"
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

    private func narrativeFallback(
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot]
    ) -> String {
        guard !events.isEmpty || !reminders.isEmpty else {
            return "No events or reminders today. A clear day for deep work."
        }
        var parts: [String] = []
        switch events.count {
        case 0:
            parts.append("No events scheduled today.")
        case 1:
            let time = events[0].startDate.formatted(.dateTime.hour().minute())
            parts.append("You have \(events[0].title) at \(time) today.")
        default:
            let listed = events.prefix(3).map {
                "\($0.title) at \($0.startDate.formatted(.dateTime.hour().minute()))"
            }
            let tail = events.count > 3 ? " and \(events.count - 3) more" : ""
            parts.append("Today: \(listed.joined(separator: ", "))\(tail).")
        }
        if !reminders.isEmpty {
            let s = reminders.count == 1 ? "" : "s"
            parts.append("\(reminders.count) reminder\(s) due.")
        }
        return parts.joined(separator: " ")
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
