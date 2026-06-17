import Foundation

/// Tabs available in the dispatch panel.
/// Extensible — add new integration tabs as cases.
///
enum DispatchTab: String, CaseIterable, Equatable, Sendable {
    case headers
    case links
    case calendar
    case reminders

    var title: String {
        switch self {
        case .headers: "Headers"
        case .links: "Links"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        }
    }

    var icon: String {
        switch self {
        case .headers: "bookmark.fill"
        case .links: "link"
        case .calendar: "calendar"
        case .reminders: "bell"
        }
    }

    /// Serif-italic headline shown when the tab has no items.
    var emptyHeadline: String {
        switch self {
        case .headers: AppStrings.Dispatch.emptyHeaders
        case .links: AppStrings.Dispatch.emptyLinks
        case .calendar: AppStrings.Dispatch.emptyCalendar
        case .reminders: AppStrings.Dispatch.emptyReminders
        }
    }

    /// Mono uppercase instruction shown under the empty-state headline.
    var emptyHint: String {
        switch self {
        case .headers: AppStrings.Dispatch.hintHeaders
        case .links: AppStrings.Dispatch.hintLinks
        case .calendar: AppStrings.Dispatch.hintCalendar
        case .reminders: AppStrings.Dispatch.hintReminders
        }
    }

    /// Label for the bottom add-action button. `nil` for tabs whose
    /// items can't be created from the dispatch menu (headers are
    /// authored on the page, not added here).
    var addLabel: String? {
        switch self {
        case .headers: nil
        case .links: AppStrings.Dispatch.addLink
        case .calendar: AppStrings.Dispatch.addCalendar
        case .reminders: AppStrings.Dispatch.addReminder
        }
    }
}
