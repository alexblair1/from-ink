import Foundation

enum Integration: String, CaseIterable, Hashable {
    case linear
    case github
    case reminders
    case calendar
    case mail

    var label: String {
        switch self {
        case .linear:    return "Linear"
        case .github:    return "GitHub"
        case .reminders: return "Reminders"
        case .calendar:  return "Calendar"
        case .mail:      return "Mail"
        }
    }

    var icon: String {
        switch self {
        case .linear:    return "checklist"
        case .github:    return "chevron.left.forwardslash.chevron.right"
        case .reminders: return "bell"
        case .calendar:  return "calendar"
        case .mail:      return "envelope"
        }
    }
}
