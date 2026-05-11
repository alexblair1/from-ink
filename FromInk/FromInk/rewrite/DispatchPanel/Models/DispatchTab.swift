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
}
