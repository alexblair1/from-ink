import Foundation
import SwiftUI

/// Pure-function namespace that turns a `StoredHighlight` plus a `now`
/// reference into the (in-progress, badge) tuple consumed by
/// `BriefEventRow.Model`. Lives at file scope so it's unit-testable
/// without spinning up the SwiftUI view hierarchy that owns the
/// adapter.
///
/// **Time semantics.** The in-progress predicate uses the caller-
/// supplied `now` (which comes from `HomeFeature.State.nowTick` — a
/// state-bound clock reference that mutates every timer tick, so
/// SwiftUI re-renders against it deterministically). Apple's
/// `Date.RelativeFormatStyle` used for the future-event text uses
/// `Date.now` internally; the two values diverge by at most one
/// tick interval (~5 seconds), which is invisible at minute/hour
/// granularity.
///
/// **Localization.** The future-event badge text is produced entirely
/// by Apple's `RelativeFormatStyle`, which handles plural forms,
/// locale numerals (Arabic-Indic, Devanagari, etc.), RTL direction,
/// and locale-specific abbreviation conventions. The only strings
/// localized in this module are the "All day" override label (from
/// `AppStrings.Home.allDay`) and the two VoiceOver labels for the
/// state icons.
///
enum EventRowResolver {

    /// Three-state classification + the badge variant to render.
    /// Returned together so the bar and badge can't disagree about
    /// whether an event is in progress.
    static func resolve(
        highlight: StoredHighlight,
        now: Date,
        calendar: Calendar
    ) -> (isInProgress: Bool, badge: BriefEventRow.Badge) {

        // Highlights without raw event timing (all-day rows,
        // malformed records) carry no time-relative state — fall
        // back to whatever string the data layer baked.
        guard let start = highlight.startDate, let end = highlight.endDate else {
            return (false, .text(highlight.trailingBadge))
        }

        // Passed: event has ended.
        if end <= now {
            return (
                false,
                .icon(
                    systemName: "checkmark",
                    color: ColorTokens.standard.ink3,
                    accessibilityLabel: AppStrings.Home.eventPassedAccessibilityLabel
                )
            )
        }

        // In progress: `start <= now < end` (mutually exclusive with
        // both passed and future — verified by mental walkthrough at
        // every boundary).
        if start <= now {
            return (
                true,
                .icon(
                    systemName: "record.circle.fill",
                    color: ColorTokens.standard.inkPure,
                    accessibilityLabel: AppStrings.Home.eventInProgressAccessibilityLabel
                )
            )
        }

        // Future: derive the relative-time badge from Apple's
        // formatter. Self-localizing + plural-aware.
        return (false, .text(futureBadgeText(start: start, end: end, now: now, calendar: calendar)))
    }

    /// "All day" for events ≥23 hours on the same local day,
    /// otherwise Apple's relative format ("in 30 min", "in 2 hr",
    /// "dans 30 min", etc.).
    ///
    /// The 23-hour heuristic catches calendar events that span almost
    /// the whole day without `isAllDay` being set — a common pattern
    /// for "Out of office" or "Conference" entries. Without the
    /// override Apple would produce "in 23 hr" which is technically
    /// correct but useless for the user's decision-making.
    static func futureBadgeText(
        start: Date,
        end: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        let hours = calendar.dateComponents([.hour], from: start, to: end).hour ?? 0
        if calendar.isDate(start, inSameDayAs: now) && hours >= 23 {
            return AppStrings.Home.allDay
        }
        return start.formatted(
            .relative(presentation: .numeric, unitsStyle: .abbreviated)
        )
    }
}
