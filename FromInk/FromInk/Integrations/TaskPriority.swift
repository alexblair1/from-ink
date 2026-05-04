import Foundation

enum TaskPriority: Int, Codable, CaseIterable, Comparable, Hashable {
    case none   = 0
    case low    = 1
    case medium = 2
    case high   = 3
    case urgent = 4

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    var icon: String {
        switch self {
        case .none:   return "minus"
        case .low:    return "arrow.down"
        case .medium: return "equal"
        case .high:   return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    /// Parse a free-text priority string from Foundation Models output.
    static func from(_ string: String) -> TaskPriority {
        switch string.lowercased().trimmingCharacters(in: .whitespaces) {
        case "urgent": return .urgent
        case "high":   return .high
        case "medium": return .medium
        case "low":    return .low
        default:       return .none
        }
    }
}
