import Foundation

/// Sendable value type derived from DailyBriefRecord.
/// Used in TCA State and across actor boundaries.
/// The @Model class stays in SwiftData — this is the view of it.
///
/// **Scope:** the brief's editorial artifact only — focus + suggestion
/// text plus the generation timestamp (used for the "synced N minutes
/// ago" label). Event/reminder counts, event rows, reminder rows, and
/// birthdays are NOT carried here; they're fetched live per-date via
/// `DailyBriefClient.fetchDayContent` and rendered from `DayContent`.
///
struct DailyBriefSnapshot: Equatable, Sendable {
    let dayKey: String
    let focusText: String
    let suggestionText: String
    let generatedAt: Date

    init(
        dayKey: String,
        focusText: String,
        suggestionText: String,
        generatedAt: Date
    ) {
        self.dayKey = dayKey
        self.focusText = focusText
        self.suggestionText = suggestionText
        self.generatedAt = generatedAt
    }
}

// MARK: - Conversion from @Model

extension DailyBriefSnapshot {
    init(record: DailyBriefRecord) {
        self.dayKey = record.dayKey
        self.focusText = record.focusText
        self.suggestionText = record.suggestionText
        self.generatedAt = record.generatedAt
    }
}
