import Foundation

/// A connected OAuth account stored in the Keychain.
/// One per connected account per provider — supports multi-account.
///
struct IntegrationAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let provider: OAuthProvider
    let displayName: String
    let token: OAuthToken
    let connectedAt: Date

    init(
        id: UUID = UUID(),
        provider: OAuthProvider,
        displayName: String,
        token: OAuthToken,
        connectedAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.token = token
        self.connectedAt = connectedAt
    }
}
