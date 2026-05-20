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
/// **What this record stores:** the FM-generated editorial text
/// (focus + suggestion), plus a cheap integer checksum of the events
/// + reminders that were present when the brief was generated. The
/// checksum is internal to `DailyBriefClient` — on launch, we compare
/// it against the live EventKit counts and skip the FM regen call
/// when they match. It's not surfaced through `DailyBriefSnapshot`
/// because nothing in the view layer needs frozen-at-generation
/// counts; the tabs render live counts from `DayContent`.
///
/// Event rows, reminder rows, birthdays, and live counts are NEVER
/// persisted — they're queried live from EventKit / Contacts per-day
/// via `DailyBriefClient.fetchDayContent`. The record never duplicates
/// system-owned data.
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

    /// EventKit event count at the moment of brief generation. Compared
    /// against live counts on `fetchOrGenerate` to decide whether the
    /// cached brief is still fresh.
    var eventCountAtGeneration: Int = 0

    /// EventKit incomplete-reminder count at the moment of brief
    /// generation. Same staleness-check role as `eventCountAtGeneration`.
    var reminderCountAtGeneration: Int = 0

    /// When this brief was generated or last regenerated.
    var generatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        dayKey: String,
        focusText: String,
        suggestionText: String,
        eventCountAtGeneration: Int,
        reminderCountAtGeneration: Int,
        generatedAt: Date
    ) {
        self.id = id
        self.dayKey = dayKey
        self.focusText = focusText
        self.suggestionText = suggestionText
        self.eventCountAtGeneration = eventCountAtGeneration
        self.reminderCountAtGeneration = reminderCountAtGeneration
        self.generatedAt = generatedAt
    }
}
