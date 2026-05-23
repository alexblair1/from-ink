import Foundation
import FoundationModels

/// Apple Foundation Models structured output for the daily brief.
///
/// `@Generable` constrains the on-device model's decoding so the
/// response parses into Swift fields without prompt-engineering JSON
/// schemas. The `@Guide` descriptions are part of the prompt the
/// framework synthesizes — keep them descriptive and tightly scoped.
///
/// Consumed by `DailyBriefClient.runFMWithRetry` via
/// `FoundationModelsService.generateBrief(prompt)`. Only `focus` and
/// `suggestion` are surfaced to the UI in V1; the other fields stay
/// for forward compatibility with richer brief renderings.
///
@Generable struct DailyBrief: Equatable {
    @Guide(description: "Time-aware greeting: 'Good morning', 'Good afternoon', or 'Good evening'. Include the user's first name if known, otherwise omit.")
    var greeting: String

    @Guide(description: "2-3 sentence paragraph summarising the day in plain English. Name specific events with their times, call out any overdue reminders by name, and end with what matters most. Write as if speaking directly to the user — no bullet points, no headers.")
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
