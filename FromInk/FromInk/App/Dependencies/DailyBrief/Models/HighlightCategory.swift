import Foundation

/// Semantic category for a stored highlight. Persisted as a stable string
/// rawValue (NOT a localized display string), so cached records survive
/// device language changes.
///
/// Display strings are resolved via `AppStrings.Home.*` at render time via
/// `displayString`.
///
/// **Event categories:** `.allDay`, `.nextUp`, `.upcoming`. All-day events
/// are always pinned ahead of timed events and never claim the
/// "next up" slot.
///
/// **Reminder categories:** `.overdue`, `.today`, `.anytime`. Overdue and
/// today are time-anchored; `.anytime` covers undated reminders and
/// reminders whose due date has no time component.
///
nonisolated enum HighlightCategory: String, Codable, Sendable {
    case allDay = "all_day"
    case nextUp = "next_up"
    case upcoming = "upcoming"

    case overdue = "overdue"
    case today = "today"
    case anytime = "anytime"
}

extension HighlightCategory {
    /// Localized display string for this category. Resolved on demand so
    /// language changes propagate immediately to UI without rewriting
    /// stored records.
    var displayString: String {
        switch self {
        case .allDay:   AppStrings.Home.allDay
        case .nextUp:   AppStrings.Home.nextUp
        case .upcoming: AppStrings.Home.upcoming
        case .overdue:  AppStrings.Home.overdue
        case .today:    AppStrings.Home.today
        case .anytime:  AppStrings.Home.anytime
        }
    }
}
