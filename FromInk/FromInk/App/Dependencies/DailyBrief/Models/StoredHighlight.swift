import Foundation

/// A highlight value carrying the data needed to render one row in the
/// Calendar / Reminders tab. Transport type: flows from
/// `_fetchDayContent` (DailyBriefClient) through `DayContent` →
/// `HomeFeature.State` → the home adapter → `BriefEventRow.Model`.
///
/// Carries raw event timing (`startDate`, `endDate`) so time-relative
/// UI concerns (in-progress, time-until, "now" badges) can be derived
/// at render time against `cal.now()` rather than baked here. Keeping
/// time-derived state out of this type is deliberate — values that
/// change minute-to-minute don't belong on a transport that's
/// equality-compared across reducer ticks.
///
struct StoredHighlight: Codable, Equatable, Sendable {
    let category: HighlightCategory
    let icon: String
    let title: String
    /// Formatted local time string ("9:30 AM") for display. Locale-
    /// formatted in the source helper (`buildHighlights`) since it's
    /// stable for the lifetime of one render cycle.
    let time: String
    /// Trailing badge text ("In 30 m", "All day", "Now"). Currently
    /// computed at source time; same locale rationale as `time`.
    let trailingBadge: String
    /// Source notebook link if the highlight is page-bound.
    let sourceNotebookID: UUID?
    let sourcePageIndex: Int?
    /// Raw event start moment. Optional because non-event highlights
    /// (reminders, all-day rows) don't have a meaningful start. Used
    /// downstream to derive the in-progress predicate at render time.
    let startDate: Date?
    /// Raw event end moment. Same optionality + derivation rules as
    /// `startDate`.
    let endDate: Date?
}
