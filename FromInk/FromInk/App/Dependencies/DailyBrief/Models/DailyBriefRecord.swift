import SwiftData
import Foundation

/// Persisted daily brief — one per day, synced via CloudKit.
/// Never deleted — accumulates as a journal for time warp.
///
/// `dayKey` is a Gregorian/POSIX "yyyy-MM-dd" string in the user's
/// timezone, produced by `CalendarContext.dayKey(_:)`. It is the
/// record's identity key — one record per user-local day.
/// `generatedAt` is the absolute moment. See dates_edd.md §7.4.
///
@Model final class DailyBriefRecord {
    var id: UUID = UUID()

    /// Gregorian day-key "2026-05-12" — one record per day.
    /// Produced by CalendarContext.dayKey(). Frozen at write time.
    var dayKey: String = ""

    /// The AI-generated focus paragraph (2-3 sentences).
    var focusText: String = ""

    /// The AI-generated actionable suggestion.
    var suggestionText: String = ""

    /// EventKit counts at generation time — used for staleness check.
    var eventCountAtGeneration: Int = 0
    var reminderCountAtGeneration: Int = 0

    /// When this brief was generated or last regenerated.
    var generatedAt: Date = Date()

    /// JSON-encoded [StoredHighlight] — frozen at generation time.
    var highlightsData: Data? = nil

    init(
        id: UUID = UUID(),
        dayKey: String,
        focusText: String,
        suggestionText: String,
        eventCountAtGeneration: Int,
        reminderCountAtGeneration: Int,
        generatedAt: Date,
        highlights: [StoredHighlight] = []
    ) {
        self.id = id
        self.dayKey = dayKey
        self.focusText = focusText
        self.suggestionText = suggestionText
        self.eventCountAtGeneration = eventCountAtGeneration
        self.reminderCountAtGeneration = reminderCountAtGeneration
        self.generatedAt = generatedAt
        self.highlightsData = try? JSONEncoder().encode(highlights)
    }
}

// MARK: - Highlight accessors

extension DailyBriefRecord {
    var highlights: [StoredHighlight] {
        guard let data = highlightsData else { return [] }
        return (try? JSONDecoder().decode([StoredHighlight].self, from: data)) ?? []
    }

    func setHighlights(_ highlights: [StoredHighlight]) {
        highlightsData = try? JSONEncoder().encode(highlights)
    }
}
