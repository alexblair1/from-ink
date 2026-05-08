import SwiftUI

// MARK: - Preview with mock data

#Preview("Home — Editorial") {
    HomeScreen(model: .preview)
        .preferredColorScheme(.light)
}

#Preview("Home — Dark") {
    HomeScreen(model: .preview)
        .preferredColorScheme(.dark)
}

#Preview("Home — Empty") {
    HomeScreen(model: .previewEmpty)
        .preferredColorScheme(.light)
}

// MARK: - Preview models

extension HomeScreen.Model {
    @MainActor static var preview: HomeScreen.Model {
        @State var searchText = ""

        return HomeScreen.Model(
            masthead: .preview,
            searchText: .constant(""),
            onSearchChanged: { _ in },
            folders: [
                .init(id: UUID(), name: "Work", notebookCount: 4, icon: "folder"),
                .init(id: UUID(), name: "Personal", notebookCount: 3, icon: "folder"),
                .init(id: UUID(), name: "Writing", notebookCount: 2, icon: "folder"),
                .init(id: UUID(), name: "Research", notebookCount: 1, icon: "folder"),
                .init(id: UUID(), name: "Sketchbook", notebookCount: 1, icon: "folder"),
                .init(id: UUID(), name: "Travel", notebookCount: 2, icon: "folder"),
            ],
            notebooks: [
                .init(id: UUID(), title: "Quarterly review", subtitle: "Page 3 of 12", coverColor: Color("ink/Ink")),
                .init(id: UUID(), title: "Morning pages", subtitle: "Page 58 of 58", coverColor: Color("ink/Ink")),
                .init(id: UUID(), title: "Interview prep", subtitle: "Page 1 of 3", coverColor: Color("ink/Ink2")),
                .init(id: UUID(), title: "Field notes", subtitle: "Page 2 of 6", coverColor: Color("ink/Ink")),
                .init(id: UUID(), title: "Book club", subtitle: "Page 4 of 9", coverColor: Color("ink/Ink3")),
                .init(id: UUID(), title: "Meeting notes", subtitle: "Page 7 of 7", coverColor: Color("ink/Ink")),
            ],
            onFolder: { _ in },
            onNotebook: { _ in },
            onNewNotebook: { }
        )
    }

    @MainActor static var previewEmpty: HomeScreen.Model {
        HomeScreen.Model(
            masthead: .preview,
            searchText: .constant(""),
            onSearchChanged: { _ in },
            folders: [],
            notebooks: [],
            onFolder: { _ in },
            onNotebook: { _ in },
            onNewNotebook: { }
        )
    }
}

extension HomeMasthead.Model {
    static var preview: HomeMasthead.Model {
        HomeMasthead.Model(
            weekday: "Wednesday",
            monthDay: "May 7",
            syncLabel: "synced 2m ago",
            briefSentence: "Three meetings, two ship-day reminders, and Carla's birthday — a heavy day with one window for deep work between 10 and noon.",
            eventCount: 4,
            reminderCount: 4,
            birthdayCount: 1,
            weather: .init(
                symbolName: "cloud.fog",
                transitionSymbol: "sun.max",
                temperature: "58°",
                sunrise: "6:14",
                sunset: "8:01"
            ),
            expandedBrief: .preview,
            onNewNotebook: { },
            onViewDetails: { }
        )
    }
}

extension HomeExpandedBrief.Model {
    static var preview: HomeExpandedBrief.Model {
        HomeExpandedBrief.Model(
            paragraphs: [
                "A heavy Wednesday. Three meetings, four reminders due, and Carla's birthday all land on the same day, with the v0.3 ship deadline at 5pm. Expect it to feel tight unless you protect the 10–noon block.",
                "The day starts soft: standup at 9:30, then nothing until your 1:1 with Maya at 11. Use the quiet hour for the build — the TestFlight reminder is flagged and the domain renewal is already two days late, both worth clearing before lunch.",
                "The afternoon turns social. Carla's interview at 2pm doubles as her 41st — Interview prep is open to page 1, and her contact card has a small note from last year worth re-reading. Dinner at Sushi Nakamura at 5:30 is just after the v0.3 cutoff, so plan to push the build before you walk over.",
                "Foggy through mid-morning, clearing for the walk. Sunset at 8:01.",
            ],
            highlights: [
                .init(icon: "calendar", label: "Next up", text: "1:1 with Maya · 11:00 at Roastery on 4th"),
                .init(icon: "checklist", label: "Overdue", text: "Renew domain — fromink.app · 2 days late"),
                .init(icon: "checklist", label: "Today", text: "Ship v0.3 build to TestFlight · 5pm, flagged"),
                .init(icon: "person.crop.circle", label: "Birthday", text: "Carla Mendez turns 41 · you're seeing her at 2pm"),
            ],
            onViewDetails: { },
            onCollapse: { }
        )
    }
}
