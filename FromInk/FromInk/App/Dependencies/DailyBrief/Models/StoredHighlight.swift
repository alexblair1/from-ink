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
    /// EventKit identifier — `EKEvent.eventIdentifier` for events and
    /// `EKCalendarItem.calendarItemIdentifier` for reminders. Used by
    /// the home adapter to look up an existing `CalendarItemLink`
    /// (signaling the linked-notebook visual treatment + driving the
    /// row tap to either "open notebook" or "present action sheet").
    /// Nil for synthesized highlights (no EK source — e.g., the future
    /// "this highlight came from a notebook" path).
    let localIdentifier: String?
    /// `EKCalendarItem.calendarItemExternalIdentifier`. Used when
    /// creating a `CalendarItemLink` so the validator can heal stale
    /// local identifiers without losing the link. Same nullability
    /// semantics as `localIdentifier`.
    let externalIdentifier: String?
    /// True when the underlying EKEvent has recurrence rules.
    /// Surfaces in the Create/Link confirmation copy as "this notebook
    /// will cover all instances of this meeting." Always false for
    /// reminders (they use a different recurrence model).
    let hasRecurrenceRules: Bool

    /// Explicit init with defaults for the EK-identifier fields so
    /// pre-existing callers / fixtures don't have to thread the new
    /// arguments at every construction site. Snapshot-based highlights
    /// without an EK source naturally produce `nil` / `false`.
    init(
        category: HighlightCategory,
        icon: String,
        title: String,
        time: String,
        trailingBadge: String,
        sourceNotebookID: UUID?,
        sourcePageIndex: Int?,
        startDate: Date?,
        endDate: Date?,
        localIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        hasRecurrenceRules: Bool = false
    ) {
        self.category = category
        self.icon = icon
        self.title = title
        self.time = time
        self.trailingBadge = trailingBadge
        self.sourceNotebookID = sourceNotebookID
        self.sourcePageIndex = sourcePageIndex
        self.startDate = startDate
        self.endDate = endDate
        self.localIdentifier = localIdentifier
        self.externalIdentifier = externalIdentifier
        self.hasRecurrenceRules = hasRecurrenceRules
    }
}
