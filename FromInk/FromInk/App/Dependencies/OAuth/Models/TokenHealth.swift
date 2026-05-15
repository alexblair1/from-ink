import Foundation

/// Derived health indicator for a token, computed by OAuthService
/// using CalendarContext for time comparison.
///
enum TokenHealth: Equatable, Sendable {
    case healthy
    case expiringSoon
    case expired
    case reconnectRequired
}
