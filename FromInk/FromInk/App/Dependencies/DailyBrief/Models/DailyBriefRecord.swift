import SwiftData
import Foundation

/// Persisted daily brief — one per day, synced via CloudKit.
///
/// `dayKey` is a Gregorian/POSIX "yyyy-MM-dd" string in the user's
/// timezone, produced by `CalendarContext.dayKey(_:)`. It is the
/// record's identity key — one record per user-local day.
/// `generatedAt` is the absolute moment. See dates_edd.md §7.4.
///
/// **What this record stores:** the FM-generated editorial text
/// (focus + suggestion), plus a cheap integer checksum of the events
/// + reminders that were present when the brief was generated. The
/// checksum is internal to `DailyBriefClient`. Event rows, reminder
/// rows, birthdays, and live counts are NEVER persisted — they're
/// queried live from EventKit / Contacts per-day via
/// `DailyBriefClient.fetchDayContent`.
///
/// **Regenerability + retention.** A brief is fully reproducible from
/// `EventKit(dayKey) + FoundationModels(prompt)`. So records are
/// "warm cache" rather than authoritative — safe to evict and
/// regenerate on demand. The LRU retention policy
/// (`evictionThreshold` / `evictionTarget`) and the touch-on-read
/// debounce (`touchInterval`) are documented in
/// `Documentation/data_model_edd.md §Retention`.
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

    /// Last time this brief was loaded from the cache into a view.
    /// Touched (with hour-granularity debounce) on every cache hit so
    /// LRU eviction can favor recently-viewed days. Distinct from
    /// `generatedAt` — `generatedAt` measures when the text was
    /// produced; `lastAccessedAt` measures when the user last read it.
    var lastAccessedAt: Date = Date()

    init(
        id: UUID = UUID(),
        dayKey: String,
        focusText: String,
        suggestionText: String,
        eventCountAtGeneration: Int,
        reminderCountAtGeneration: Int,
        generatedAt: Date,
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.focusText = focusText
        self.suggestionText = suggestionText
        self.eventCountAtGeneration = eventCountAtGeneration
        self.reminderCountAtGeneration = reminderCountAtGeneration
        self.generatedAt = generatedAt
        // Default lastAccessedAt to generatedAt so a freshly minted
        // record reads as "accessed now" without callers having to
        // supply both timestamps.
        self.lastAccessedAt = lastAccessedAt ?? generatedAt
    }
}

// MARK: - Retention policy

extension DailyBriefRecord {
    /// LRU eviction kicks in when the total record count exceeds this
    /// number. See `Documentation/data_model_edd.md §Retention` for
    /// the reasoning. Tune here; downstream code reads through these
    /// constants so the policy stays in one place.
    static let evictionThreshold: Int = 5_000

    /// When eviction runs, drop the total count to this number. The
    /// gap between threshold and target gives the system a hysteresis
    /// band — without it, every subsequent write would trigger a
    /// single-record eviction.
    static let evictionTarget: Int = 4_500

    /// Minimum interval between `lastAccessedAt` updates for the same
    /// record. Reads happen on every appeared / foregrounded / wheel
    /// scroll; saving on every read would dirty the store and CloudKit
    /// for no signal. Hour-granularity is plenty for LRU.
    static let touchInterval: TimeInterval = 60 * 60
}
