import Foundation

/// Lightweight, fast-to-fetch snapshot of "what's happening on this day" —
/// the events, reminders, and birthdays. Has no FM-generated content
/// (no focus text, no editor's note); strictly factual.
///
/// Lives in parallel to `DailyBriefSnapshot`. While the brief snapshot is
/// the heavyweight editorial artifact (slow to generate, persisted in
/// SwiftData as a `DailyBriefRecord`), `DayContent` is the data the
/// brief tabs render — readable from EventKit / Contacts without
/// invoking Foundation Models.
///
/// Splitting the two lets the Time Warp wheel scrub through days at
/// high frequency without firing any FM work. Brief generation only
/// happens when the wheel dismisses on a day with no existing record.
///
nonisolated struct DayContent: Equatable, Sendable {
    let dayKey: String
    let events: [StoredHighlight]
    let reminders: [StoredHighlight]
    let birthdays: [StoredBirthday]
    let eventCount: Int
    let reminderCount: Int
    let birthdayCount: Int

    init(
        dayKey: String,
        events: [StoredHighlight] = [],
        reminders: [StoredHighlight] = [],
        birthdays: [StoredBirthday] = [],
        eventCount: Int? = nil,
        reminderCount: Int? = nil,
        birthdayCount: Int? = nil
    ) {
        self.dayKey = dayKey
        self.events = events
        self.reminders = reminders
        self.birthdays = birthdays
        // Defaults derive count from the array length unless the caller
        // overrides (e.g., counts include all-day events that aren't in
        // the highlight list).
        self.eventCount = eventCount ?? events.count
        self.reminderCount = reminderCount ?? reminders.count
        self.birthdayCount = birthdayCount ?? birthdays.count
    }

    /// Empty content for a day with nothing scheduled.
    static func empty(dayKey: String) -> DayContent {
        DayContent(dayKey: dayKey)
    }
}
