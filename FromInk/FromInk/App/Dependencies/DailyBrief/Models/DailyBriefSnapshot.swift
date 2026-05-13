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
    let generatedAt: Date
    let highlights: [StoredHighlight]
}

// MARK: - Conversion from @Model

extension DailyBriefSnapshot {
    init(record: DailyBriefRecord) {
        self.dayKey = record.dayKey
        self.focusText = record.focusText
        self.suggestionText = record.suggestionText
        self.eventCount = record.eventCountAtGeneration
        self.reminderCount = record.reminderCountAtGeneration
        self.generatedAt = record.generatedAt
        self.highlights = record.highlights
    }
}
