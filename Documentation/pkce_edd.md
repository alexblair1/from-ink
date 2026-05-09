# From Ink — PKCE Authentication System Engineering Design

> **Status:** Draft
> **Last updated:** 2026-05-08
> **Authors:** Engineering

---

## 1. Goal

Build a single, reusable PKCE (RFC 7636) authentication system that handles OAuth 2.0 for all third-party integrations. One system, seven integrations, zero server infrastructure.

**Confirmed integrations (from Integration-Matrix.md):**

| Integration | PKCE | Notes |
|---|---|---|
| Linear | S256 | Documented |
| GitHub | S256 | Confirmed July 2025 |
| Slack | S256 | Required for custom URI schemes (March 2026) |
| Canva | S256 | Required |
| Asana | S256 | Confirmed |
| Todoist | S256 | Dynamic Client Registration, no client secret |
| Airtable | S256 | Client secret optional for native apps |

---

## 2. Design Principles

1. **One generic PKCE engine.** The auth flow is identical for every integration — only the URLs, scopes, and client IDs differ. Provider-specific details are configuration, not code.
2. **No client secrets in the app bundle.** PKCE eliminates the need. If a provider requires a client secret, it is not integrated (see Integration-Matrix.md).
3. **No server infrastructure.** The entire OAuth flow happens on-device: `ASWebAuthenticationSession` for the redirect, `SecRandomCopyBytes` for the verifier, `SHA256` for the challenge.
4. **Multi-account per integration.** A user may have multiple Linear workspaces or GitHub accounts. The system stores `IdentifiedArrayOf<IntegrationAccount>` per provider in the Keychain.
5. **Token lifecycle is automatic.** Access tokens refresh silently. The user only sees the auth UI when initial authorization is needed or when a refresh token is revoked.
6. **TCA-native.** The auth system is a TCA dependency client with explicit state transitions, testable with `TestStore`.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  TCA Features                    │
│  (DispatchFeature, IntegrationFeature, etc.)     │
│                                                  │
│  @Dependency(\.oauthService) var oauthService    │
│  @Dependency(\.keychainService) var keychain     │
├─────────────────────────────────────────────────┤
│              OAuthService (TCA Client)           │
│                                                  │
│  authorize(provider:) → Token                    │
│  refresh(provider:accountID:) → Token            │
│  revoke(provider:accountID:)                     │
│  token(for:accountID:) → Token?                  │
├─────────────────────────────────────────────────┤
│              PKCEEngine (internal)               │
│                                                  │
│  generateVerifier() → String                     │
│  generateChallenge(verifier:) → String           │
│  buildAuthURL(config:verifier:) → URL            │
│  exchangeCode(config:code:verifier:) → Token     │
│  refreshToken(config:refreshToken:) → Token      │
├─────────────────────────────────────────────────┤
│          ASWebAuthenticationSession              │
│          (system browser, redirect capture)       │
├─────────────────────────────────────────────────┤
│          KeychainService (TCA Client)            │
│                                                  │
│  save(account:for:)                              │
│  load(provider:) → [IntegrationAccount]          │
│  delete(accountID:provider:)                     │
│  (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) │
└─────────────────────────────────────────────────┘
```

---

## 4. Provider Configuration

Every integration is described by a static `OAuthProviderConfig`. No integration-specific code — just data.

```swift
struct OAuthProviderConfig: Sendable {
    let provider: Integration
    let clientID: String
    let authorizeURL: URL
    let tokenURL: URL
    let revokeURL: URL?
    let scopes: [String]
    let callbackURLScheme: String    // "fromink"
    let redirectPath: String         // "/oauth/linear", "/oauth/github", etc.

    var redirectURI: String {
        "\(callbackURLScheme)://\(redirectPath)"
    }
}
```

### Provider Configs

```swift
extension OAuthProviderConfig {
    static let linear = OAuthProviderConfig(
        provider: .linear,
        clientID: "/* registered at linear.app/settings/api */",
        authorizeURL: URL(string: "https://linear.app/oauth/authorize")!,
        tokenURL: URL(string: "https://api.linear.app/oauth/token")!,
        revokeURL: URL(string: "https://api.linear.app/oauth/revoke")!,
        scopes: ["read", "write", "issues:create"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/linear"
    )

    static let github = OAuthProviderConfig(
        provider: .github,
        clientID: "/* registered at github.com/settings/developers */",
        authorizeURL: URL(string: "https://github.com/login/oauth/authorize")!,
        tokenURL: URL(string: "https://github.com/login/oauth/access_token")!,
        revokeURL: nil,   // GitHub doesn't support programmatic token revocation
        scopes: ["repo"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/github"
    )

    static let slack = OAuthProviderConfig(
        provider: .slack,
        clientID: "/* registered at api.slack.com/apps */",
        authorizeURL: URL(string: "https://slack.com/openid/connect/authorize")!,
        tokenURL: URL(string: "https://slack.com/api/openid.connect.token")!,
        revokeURL: URL(string: "https://slack.com/api/auth.revoke")!,
        scopes: ["openid", "chat:write", "channels:read"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/slack"
    )

    static let canva = OAuthProviderConfig(
        provider: .canva,
        clientID: "/* registered at canva.com/developers */",
        authorizeURL: URL(string: "https://www.canva.com/api/oauth/authorize")!,
        tokenURL: URL(string: "https://www.canva.com/api/oauth/token")!,
        revokeURL: URL(string: "https://www.canva.com/api/oauth/revoke")!,
        scopes: ["design:content:read", "design:content:write"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/canva"
    )

    static let asana = OAuthProviderConfig(
        provider: .asana,
        clientID: "/* registered at app.asana.com/0/developer-console */",
        authorizeURL: URL(string: "https://app.asana.com/-/oauth_authorize")!,
        tokenURL: URL(string: "https://app.asana.com/-/oauth_token")!,
        revokeURL: nil,
        scopes: ["default"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/asana"
    )

    static let todoist = OAuthProviderConfig(
        provider: .todoist,
        clientID: "/* registered at developer.todoist.com */",
        authorizeURL: URL(string: "https://todoist.com/oauth/authorize")!,
        tokenURL: URL(string: "https://todoist.com/oauth/access_token")!,
        revokeURL: URL(string: "https://api.todoist.com/sync/v9/access_tokens/revoke")!,
        scopes: ["data:read_write"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/todoist"
    )

    static let airtable = OAuthProviderConfig(
        provider: .airtable,
        clientID: "/* registered at airtable.com/create/oauth */",
        authorizeURL: URL(string: "https://airtable.com/oauth2/v1/authorize")!,
        tokenURL: URL(string: "https://airtable.com/oauth2/v1/token")!,
        revokeURL: nil,
        scopes: ["data.records:read", "data.records:write", "schema.bases:read"],
        callbackURLScheme: "fromink",
        redirectPath: "/oauth/airtable"
    )

    static let all: [OAuthProviderConfig] = [
        .linear, .github, .slack, .canva, .asana, .todoist, .airtable
    ]
}
```

### Deep Link Scheme

All providers share the same custom URL scheme: `fromink://`. The redirect path differentiates them.

**Info.plist:**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>fromink</string>
        </array>
    </dict>
</array>
```

---

## 5. PKCE Engine

The cryptographic core. Stateless, pure functions, no side effects.

```swift
enum PKCEEngine {

    /// 32 cryptographically random bytes, base64url-encoded.
    static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// SHA256 hash of the verifier, base64url-encoded. Always S256.
    static func generateChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// Build the authorization URL with PKCE parameters.
    static func buildAuthorizationURL(
        config: OAuthProviderConfig,
        verifier: String,
        state: String
    ) -> URL {
        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: generateChallenge(from: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}
```

### Base64URL Encoding

```swift
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

---

## 6. Token Model

```swift
struct OAuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let tokenType: String
    let scope: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}
```

### Integration Account

Stored in Keychain. One per connected account per provider.

```swift
struct IntegrationAccount: Identifiable, Codable, Sendable {
    let id: UUID
    let provider: Integration
    let displayName: String      // "alex@linear.app", "alexblair (GitHub)", workspace name
    let token: OAuthToken
    let connectedAt: Date
}
```

---

## 7. OAuthService (TCA Dependency Client)

```swift
struct OAuthService: Sendable {

    /// Start the full PKCE flow: browser → redirect → code exchange → token.
    /// Returns the new IntegrationAccount on success.
    var authorize: @Sendable (OAuthProviderConfig) async throws -> IntegrationAccount

    /// Silently refresh an expired access token using the stored refresh token.
    /// Updates the account in the Keychain. Returns the new token.
    var refresh: @Sendable (OAuthProviderConfig, UUID) async throws -> OAuthToken

    /// Revoke the token (if the provider supports it) and delete from Keychain.
    var revoke: @Sendable (OAuthProviderConfig, UUID) async throws -> Void

    /// Get a valid token for an account, refreshing if expired.
    /// This is what API call sites use — they never touch the auth flow directly.
    var validToken: @Sendable (OAuthProviderConfig, UUID) async throws -> OAuthToken
}

extension DependencyValues {
    var oauthService: OAuthService {
        get { self[OAuthService.self] }
        set { self[OAuthService.self] = newValue }
    }
}
```

### Live Implementation Flow

```
authorize(config)
    │
    ├── 1. Generate code verifier (32 random bytes → base64url)
    ├── 2. Generate state parameter (UUID string, for CSRF protection)
    ├── 3. Build authorization URL with PKCE challenge
    ├── 4. Present ASWebAuthenticationSession
    │       └── User authenticates in system browser
    │       └── Provider redirects to fromink://oauth/{provider}?code=XXX&state=YYY
    ├── 5. Validate state matches (CSRF check)
    ├── 6. Exchange authorization code + verifier for tokens
    │       └── POST to config.tokenURL
    │       └── Body: grant_type, code, redirect_uri, client_id, code_verifier
    │       └── Parse response → OAuthToken
    ├── 7. Fetch user profile (provider-specific) for displayName
    ├── 8. Create IntegrationAccount
    ├── 9. Save to Keychain via KeychainService
    └── 10. Return IntegrationAccount
```

### Code Verifier Lifecycle

The code verifier is generated at step 1 and held **in memory only** for the duration of steps 1–6. It is never persisted to disk, Keychain, UserDefaults, or any other storage. After the code exchange completes (or fails), the verifier is released.

```swift
// Inside authorize(config:)
let verifier = PKCEEngine.generateVerifier()  // in memory
let state = UUID().uuidString                  // in memory

let authURL = PKCEEngine.buildAuthorizationURL(config: config, verifier: verifier, state: state)
let callbackURL = try await presentAuthSession(url: authURL, scheme: config.callbackURLScheme)

// Validate state
guard let returnedState = callbackURL.queryValue(for: "state"), returnedState == state else {
    throw OAuthError.stateMismatch
}

let code = callbackURL.queryValue(for: "code")!
let token = try await exchangeCode(config: config, code: code, verifier: verifier)
// verifier goes out of scope here — never stored
```

---

## 8. KeychainService (TCA Dependency Client)

```swift
struct KeychainService: Sendable {

    /// Save or update an integration account.
    var save: @Sendable (IntegrationAccount) async throws -> Void

    /// Load all accounts for a provider.
    var accounts: @Sendable (Integration) async throws -> [IntegrationAccount]

    /// Load a specific account by ID.
    var account: @Sendable (UUID) async throws -> IntegrationAccount?

    /// Delete an account.
    var delete: @Sendable (UUID) async throws -> Void
}

extension DependencyValues {
    var keychainService: KeychainService {
        get { self[KeychainService.self] }
        set { self[KeychainService.self] = newValue }
    }
}
```

### Storage Details

- **Accessibility:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — available after first unlock, not synced to other devices via iCloud Keychain (tokens are device-local; each device authenticates independently).
- **Service key:** `"com.fromink.oauth"`
- **Account key:** `"{provider.rawValue}-{account.id}"` (e.g., `"linear-550e8400-..."`)
- **Data:** JSON-encoded `IntegrationAccount` via `JSONEncoder`

### Why Not Sync Tokens via iCloud Keychain?

OAuth tokens are device-specific credentials. Syncing them introduces:
- Race conditions on token refresh (two devices refresh the same token simultaneously, one invalidates the other)
- Revocation ambiguity (user disconnects on iPad, iPhone still has a valid token)
- Security surface expansion (a compromised iCloud account leaks all integration tokens)

Each device authenticates independently. The user connects Linear on their iPhone and separately on their iPad. This matches how most OAuth apps work.

---

## 9. Auth State Machine

Each integration connection has an explicit state, modeled in TCA:

```swift
enum AuthConnectionState: Equatable {
    case disconnected
    case connecting                  // ASWebAuthenticationSession is active
    case connected(IntegrationAccount)
    case refreshing(IntegrationAccount)  // silent token refresh in progress
    case failed(String)              // error message
}
```

### State Transitions

```
disconnected ──[user taps Connect]──→ connecting
connecting ──[auth succeeds]──→ connected
connecting ──[auth fails/cancelled]──→ failed → disconnected

connected ──[token expired, API call]──→ refreshing
refreshing ──[refresh succeeds]──→ connected (new token)
refreshing ──[refresh fails 401]──→ disconnected (re-auth needed)

connected ──[user taps Disconnect]──→ disconnected (revoke + delete)
```

---

## 10. Token Refresh Strategy

API call sites never check token expiry directly. They call `oauthService.validToken(config, accountID)`, which:

1. Loads the account from Keychain
2. Checks `token.isExpired`
3. If valid → returns the token
4. If expired → calls `refresh(config, accountID)`
5. If refresh fails with 401 → throws `OAuthError.reauthorizationRequired`
6. Feature reducer catches the error and transitions state to `.disconnected`, prompting re-auth

```swift
// In any feature that makes API calls:
case .createLinearIssue(let task):
    return .run { send in
        let token = try await oauthService.validToken(.linear, accountID)
        // token is guaranteed fresh — make the API call
        try await linearAPI.createIssue(task, token: token.accessToken)
        await send(.issueCreated)
    } catch: { error, send in
        if case OAuthError.reauthorizationRequired = error {
            await send(.authExpired(.linear))
        }
    }
```

---

## 11. ASWebAuthenticationSession Integration

```swift
@MainActor
func presentAuthSession(url: URL, scheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: scheme
        ) { callbackURL, error in
            if let error {
                continuation.resume(throwing: OAuthError.browserFailed(error))
            } else if let callbackURL {
                continuation.resume(returning: callbackURL)
            } else {
                continuation.resume(throwing: OAuthError.noCallback)
            }
        }
        session.presentationContextProvider = /* window scene provider */
        session.prefersEphemeralWebBrowserSession = false  // allow saved logins
        session.start()
    }
}
```

**Why `ASWebAuthenticationSession`, not `WKWebView` or `SFSafariViewController`?**
- `ASWebAuthenticationSession` is the only Apple-blessed mechanism for OAuth redirects
- It captures the custom URL scheme redirect automatically
- It shares cookies with Safari (SSO for services the user is already signed into)
- It prevents the app from observing the user's credentials (unlike `WKWebView`)

---

## 12. Error Types

```swift
enum OAuthError: Error {
    case stateMismatch                    // CSRF — returned state doesn't match
    case browserFailed(Error)             // ASWebAuthenticationSession error
    case noCallback                       // Session completed without URL
    case codeExchangeFailed(Int, String)  // HTTP status + body from token endpoint
    case refreshFailed(Int, String)       // HTTP status + body from token endpoint
    case reauthorizationRequired          // Refresh token revoked, need full re-auth
    case permissionDenied                 // User denied authorization
    case noAccount                        // Account not found in Keychain
    case keychainError(OSStatus)          // Keychain operation failed
}
```

---

## 13. Integration with TCA

### IntegrationFeature Reducer (sketch)

```swift
@Reducer
struct IntegrationFeature {
    @ObservableState
    struct State: Equatable {
        var connections: IdentifiedArrayOf<ConnectionState> = []

        struct ConnectionState: Equatable, Identifiable {
            let id: Integration       // provider is the identity
            var auth: AuthConnectionState = .disconnected
            var accounts: [IntegrationAccount] = []
        }
    }

    enum Action {
        case connect(Integration)
        case disconnect(Integration, accountID: UUID)
        case authCompleted(Integration, IntegrationAccount)
        case authFailed(Integration, String)
        case authExpired(Integration)
    }

    @Dependency(\.oauthService) var oauthService
    @Dependency(\.keychainService) var keychain

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .connect(let provider):
                guard let config = OAuthProviderConfig.all.first(where: { $0.provider == provider }) else {
                    return .none
                }
                state.connections[id: provider]?.auth = .connecting
                return .run { send in
                    let account = try await oauthService.authorize(config)
                    await send(.authCompleted(provider, account))
                } catch: { error, send in
                    await send(.authFailed(provider, error.localizedDescription))
                }

            case .authCompleted(let provider, let account):
                state.connections[id: provider]?.auth = .connected(account)
                state.connections[id: provider]?.accounts.append(account)
                return .none

            case .disconnect(let provider, let accountID):
                let config = OAuthProviderConfig.all.first { $0.provider == provider }!
                state.connections[id: provider]?.accounts.removeAll { $0.id == accountID }
                if state.connections[id: provider]?.accounts.isEmpty == true {
                    state.connections[id: provider]?.auth = .disconnected
                }
                return .run { _ in
                    try? await oauthService.revoke(config, accountID)
                    try? await keychain.delete(accountID)
                }

            case .authFailed(let provider, let message):
                state.connections[id: provider]?.auth = .failed(message)
                return .none

            case .authExpired(let provider):
                state.connections[id: provider]?.auth = .disconnected
                return .none
            }
        }
    }
}
```

---

## 14. Testing

### Test Values

```swift
extension OAuthService: DependencyKey {
    static var testValue: OAuthService {
        OAuthService(
            authorize: { _ in
                IntegrationAccount(
                    id: UUID(),
                    provider: .linear,
                    displayName: "Test Workspace",
                    token: OAuthToken(
                        accessToken: "test-access-token",
                        refreshToken: "test-refresh-token",
                        expiresAt: Date().addingTimeInterval(3600),
                        tokenType: "Bearer",
                        scope: "read write"
                    ),
                    connectedAt: Date()
                )
            },
            refresh: { _, _ in
                OAuthToken(
                    accessToken: "refreshed-token",
                    refreshToken: "new-refresh-token",
                    expiresAt: Date().addingTimeInterval(3600),
                    tokenType: "Bearer",
                    scope: "read write"
                )
            },
            revoke: { _, _ in },
            validToken: { _, _ in
                OAuthToken(
                    accessToken: "valid-token",
                    refreshToken: nil,
                    expiresAt: Date().addingTimeInterval(3600),
                    tokenType: "Bearer",
                    scope: nil
                )
            }
        )
    }
}

extension KeychainService: DependencyKey {
    static var testValue: KeychainService {
        let storage = LockIsolated<[UUID: IntegrationAccount]>([:])
        return KeychainService(
            save: { account in storage.withValue { $0[account.id] = account } },
            accounts: { provider in storage.withValue { $0.values.filter { $0.provider == provider } } },
            account: { id in storage.withValue { $0[id] } },
            delete: { id in storage.withValue { $0[id] = nil } }
        )
    }
}
```

### TestStore Example

```swift
func test_connect_linear_success() async {
    let store = TestStore(
        initialState: IntegrationFeature.State(
            connections: [.init(id: .linear)]
        ),
        reducer: { IntegrationFeature() },
        withDependencies: {
            $0.oauthService.authorize = { _ in
                IntegrationAccount(
                    id: UUID(0),
                    provider: .linear,
                    displayName: "Acme Inc",
                    token: .mock,
                    connectedAt: Date()
                )
            }
        }
    )

    await store.send(.connect(.linear)) {
        $0.connections[id: .linear]?.auth = .connecting
    }

    await store.receive(.authCompleted(.linear, .mock)) {
        $0.connections[id: .linear]?.auth = .connected(.mock)
        $0.connections[id: .linear]?.accounts = [.mock]
    }
}
```

---

## 15. Security Checklist

- [ ] Code verifier: 32 bytes from `SecRandomCopyBytes`, base64url-encoded
- [ ] Code challenge: `BASE64URL(SHA256(verifier))`, always S256, never plain
- [ ] Code verifier held in memory only — never persisted to disk, Keychain, UserDefaults, or logs
- [ ] State parameter: random UUID, validated on callback (CSRF protection)
- [ ] Tokens stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [ ] Tokens not synced via iCloud Keychain — each device authenticates independently
- [ ] No client secrets in app bundle, Info.plist, or source code
- [ ] `ASWebAuthenticationSession` is the only auth presentation — no `WKWebView`, no `SFSafariViewController`
- [ ] Refresh token rotation: if provider returns a new refresh token, old one is replaced
- [ ] Token revocation attempted on disconnect (best-effort — not all providers support it)
- [ ] No token logging — access tokens and refresh tokens never appear in OSLog or ErrorLogger

---

## 16. Open Questions

| # | Question | Impact |
|---|---|---|
| 1 | Should `Integration` enum be extended with the new providers (Canva, Asana, Todoist, Airtable), or should V2 providers use a separate type? | Affects the entire routing/dispatch pipeline. Extending `Integration` is simpler but couples V1 and V2 code. |
| 2 | How do we handle Todoist's Dynamic Client Registration? | Todoist may require a registration step before the standard PKCE flow. Needs investigation. |
| 3 | Should the settings screen show connection status for all 7 providers, or only ones the user has expressed interest in? | UX decision — showing all 7 could overwhelm; showing only enabled ones requires a discovery/marketplace UI. |
| 4 | How do we fetch `displayName` for each provider? | Each provider has a different "get current user" API endpoint. This is the one provider-specific piece of code needed per integration. |
| 5 | Should we support multiple accounts per provider in V1, or defer to V2? | Multi-account (e.g., personal + work GitHub) is architecturally supported but adds UI complexity. |
| 6 | Where does the `OAuthProviderConfig.clientID` live? | It's not a secret (PKCE eliminates that concern), but it's environment-specific. Options: build configuration, xcconfig file, or hardcoded constants. |
