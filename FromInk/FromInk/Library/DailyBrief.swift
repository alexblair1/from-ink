import Foundation
import FoundationModels

// MARK: - Foundation Models output type

@Generable struct DailyBrief: Equatable {
    @Guide(description: "Time-aware greeting: 'Good morning', 'Good afternoon', or 'Good evening'. Include the user's first name if known, otherwise omit.")
    var greeting: String

    @Guide(description: "2–3 sentence paragraph summarising the day in plain English. Name specific events with their times, call out any overdue reminders by name, and end with what matters most. Write as if speaking directly to the user — no bullet points, no headers.")
    var focus: String

    @Guide(description: "Today's events in chronological order, max 5.")
    var schedule: [BriefEvent]

    @Guide(description: "Overdue or due-today reminders that need attention, max 3. Exact reminder titles.")
    var urgentReminders: [String]

    @Guide(description: "Unrouted tasks from recent From Ink notebooks that haven't been sent to any integration yet, max 3.")
    var pendingFromInk: [String]

    @Guide(description: "An optional actionable insight or suggestion based on the schedule and tasks. Empty string if nothing meaningful to add.")
    var suggestion: String

    @Generable struct BriefEvent: Equatable {
        @Guide(description: "Formatted start time, e.g. '10:00 AM'.")
        var time: String

        @Guide(description: "Event title, cleaned up for display.")
        var title: String

        @Guide(description: "Brief contextual note about the event, or empty string.")
        var note: String
    }
}

// MARK: - Fallback (no Apple Intelligence)

extension DailyBrief {
    static func raw(
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot]
    ) -> DailyBrief {
        DailyBrief(
            greeting: currentGreeting(),
            focus: events.first?.title ?? "No events scheduled today.",
            schedule: events.prefix(5).map {
                BriefEvent(
                    time: $0.startDate.formatted(.dateTime.hour().minute()),
                    title: $0.title,
                    note: ""
                )
            },
            urgentReminders: reminders.prefix(3).map(\.title),
            pendingFromInk: [],
            suggestion: ""
        )
    }

    private static func currentGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        default:      return "Good evening."
        }
    }
}

// MARK: - Weather attribution snapshot

struct WeatherAttributionSnapshot: Equatable, Sendable {
    let legalPageURL: URL
    let lightLogoURL: URL
    let darkLogoURL: URL
}
