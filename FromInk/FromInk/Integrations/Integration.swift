import Foundation

/// Dispatch routing destinations. Covers native Apple integrations
/// (no OAuth needed) and third-party OAuth providers.
///
/// Apple integrations that require no user interaction or permission
/// (URL schemes, UIActivityViewController, UIPencilInteraction, etc.)
/// are not modeled here — they're implementation details of the
/// routing layer, not user-facing integration choices.
///
enum Integration: String, CaseIterable, Codable, Hashable {

    // MARK: - Third-party OAuth

    case linear
    case slack

    // MARK: - Apple (permission required)

    case reminders
    case calendar
    case contacts

    // MARK: - Apple (no permission)

    case mail
    case messages

    var label: String {
        switch self {
        case .linear:    return "Linear"
        case .slack:     return "Slack"
        case .reminders: return "Reminders"
        case .calendar:  return "Calendar"
        case .contacts:  return "Contacts"
        case .mail:      return "Mail"
        case .messages:  return "Messages"
        }
    }

    var icon: String {
        switch self {
        case .linear:    return "checklist"
        case .slack:     return "number"
        case .reminders: return "bell"
        case .calendar:  return "calendar"
        case .contacts:  return "person.crop.circle"
        case .mail:      return "envelope"
        case .messages:  return "message"
        }
    }

    /// The OAuth provider for this integration, if auth is required.
    /// Native Apple integrations return nil.
    var oauthProvider: OAuthProvider? {
        switch self {
        case .linear:    return .linear
        case .slack:     return .slack
        case .reminders: return nil
        case .calendar:  return nil
        case .contacts:  return nil
        case .mail:      return nil
        case .messages:  return nil
        }
    }

    /// Whether this integration requires a system permission prompt.
    var requiresPermission: Bool {
        switch self {
        case .reminders, .calendar, .contacts: return true
        case .linear, .slack, .mail, .messages: return false
        }
    }
}

/// Apple capabilities that require system permissions but are not
/// dispatch routing destinations. Used by feature code directly.
///
enum PermissionedCapability: String, CaseIterable, Sendable {
    case calendar
    case reminders
    case contacts
    case documentScanning
    case weather
}
