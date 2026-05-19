import Foundation

/// Sendable value type derived from DailyBriefRecord.
/// Used in TCA State and across actor boundaries.
/// The @Model class stays in SwiftData — this is the view of it.
///
struct DailyBriefSnapshot: Equatable, Sendable {
    let dayKey: String
    let focusText: String
    let suggestionText: String
    let eventCount: Int
    let reminderCount: Int
    /// Count of birthdays falling on this day. Added in the tab-rework
    /// slice; sourced from `Contacts` once the Contacts pipeline lands.
    let birthdayCount: Int
    let generatedAt: Date
    let highlights: [StoredHighlight]
    /// Birthday cards for this day's brief. Empty until the Contacts
    /// pipeline ships — the brief renders the empty state.
    let birthdays: [StoredBirthday]

    init(
        dayKey: String,
        focusText: String,
        suggestionText: String,
        eventCount: Int,
        reminderCount: Int,
        birthdayCount: Int = 0,
        generatedAt: Date,
        highlights: [StoredHighlight],
        birthdays: [StoredBirthday] = []
    ) {
        self.dayKey = dayKey
        self.focusText = focusText
        self.suggestionText = suggestionText
        self.eventCount = eventCount
        self.reminderCount = reminderCount
        self.birthdayCount = birthdayCount
        self.generatedAt = generatedAt
        self.highlights = highlights
        self.birthdays = birthdays
    }
}

// MARK: - Conversion from @Model

extension DailyBriefSnapshot {
    init(record: DailyBriefRecord) {
        self.dayKey = record.dayKey
        self.focusText = record.focusText
        self.suggestionText = record.suggestionText
        self.eventCount = record.eventCountAtGeneration
        self.reminderCount = record.reminderCountAtGeneration
        // Birthdays aren't persisted yet — pulled live from Contacts. Zero
        // until that pipeline lands.
        self.birthdayCount = 0
        self.generatedAt = record.generatedAt
        self.highlights = record.highlights
        self.birthdays = []
    }
}
