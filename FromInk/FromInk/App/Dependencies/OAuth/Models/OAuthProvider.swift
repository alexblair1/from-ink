import Foundation

/// The set of third-party services that require PKCE OAuth authentication.
/// Separate from `Integration` which covers dispatch routing (including
/// native Apple integrations that need no auth).
///
/// V1: Linear and Slack only — both are pure public clients (PKCE replaces
/// client secret, no server infrastructure needed).
///
enum OAuthProvider: String, CaseIterable, Codable, Hashable, Sendable {
    case linear
    case slack
}
