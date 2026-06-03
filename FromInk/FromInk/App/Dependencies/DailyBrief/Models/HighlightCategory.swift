import Foundation

/// Semantic category for a stored highlight. Stable string rawValue
/// (NOT a localized display string), so transport-layer values survive
/// device language changes.
///
/// Display strings resolve via `AppStrings.Home.*` at render time via
/// `displayString`.
///
/// **Event categories:** `.allDay`, `.upcoming`. All-day events are
/// always pinned ahead of timed events. The "in progress" state
/// (event happening right now) is a UI concern derived at render
/// time from `StoredHighlight.startDate`/`endDate` against `now`;
/// it lives nowhere on the data layer.
///
/// **Reminder categories:** `.overdue`, `.today`, `.anytime`. Overdue
/// and today are time-anchored; `.anytime` covers undated reminders
/// and reminders whose due date has no time component.
///
nonisolated enum HighlightCategory: String, Codable, Sendable {
    case allDay = "all_day"
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
        case .upcoming: AppStrings.Home.upcoming
        case .overdue:  AppStrings.Home.overdue
        case .today:    AppStrings.Home.today
        case .anytime:  AppStrings.Home.anytime
        }
    }
}
