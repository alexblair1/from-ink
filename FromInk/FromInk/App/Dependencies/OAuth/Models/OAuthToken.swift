import Foundation

/// OAuth token pair returned from a token endpoint.
/// No `isExpired` computed property — expiry checks use CalendarContext
/// in OAuthService.validToken to keep bare Date() out of value types.
///
struct OAuthToken: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let tokenType: String
    let scope: String?
}
