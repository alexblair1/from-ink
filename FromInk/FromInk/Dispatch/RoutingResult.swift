import Foundation

struct RoutingResult: Sendable {
    let integration: Integration
    let destinationURL: String
    let eventKitIdentifier: String?

    init(integration: Integration, destinationURL: String, eventKitIdentifier: String? = nil) {
        self.integration = integration
        self.destinationURL = destinationURL
        self.eventKitIdentifier = eventKitIdentifier
    }
}

enum RoutingOutcome: Sendable {
    case success(RoutingResult)
    case needsCalendarUI
}

enum RoutingError: LocalizedError, Sendable {
    case permissionDenied(Integration)
    case saveFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let integration):
            return "From Ink needs \(integration.label) access to route this task. Open Settings to grant permission."
        case .saveFailed(let message):
            return message
        case .userCancelled:
            return nil
        }
    }
}
