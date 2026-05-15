import AuthenticationServices
import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "OAuth")

/// Threshold for "expiring soon" health check — 24 hours in seconds.
private let expiringSoonThreshold: TimeInterval = 24 * 3600

/// TCA dependency client for the full PKCE OAuth lifecycle.
/// authorize → refresh → revoke → validToken.
///
struct OAuthService: Sendable {
    /// Full PKCE flow: browser → redirect → code exchange → token → Keychain.
    var authorize: @Sendable (OAuthProviderConfig) async throws -> IntegrationAccount

    /// Silently refresh an expired access token. Updates the Keychain.
    var refresh: @Sendable (OAuthProviderConfig, UUID) async throws -> OAuthToken

    /// Revoke the token (best-effort) and delete from Keychain.
    var revoke: @Sendable (OAuthProviderConfig, UUID) async throws -> Void

    /// Get a valid token, refreshing if expired. Single entry point for API callers.
    var validToken: @Sendable (OAuthProviderConfig, UUID) async throws -> OAuthToken

    /// Check token health for a given account without refreshing.
    var tokenHealth: @Sendable (UUID) async throws -> TokenHealth

    /// Sweep all accounts and refresh tokens expiring within the given interval.
    var sweepExpiring: @Sendable (TimeInterval) async -> Void
}

// MARK: - DependencyKey

extension OAuthService: DependencyKey {
    /// Minimal fallback — not a functioning implementation.
    /// The real live client is built via .live() factory in AppDependencyContainer.
    static let liveValue = OAuthService(
        authorize: { _ in throw CancellationError() },
        refresh: { _, _ in throw CancellationError() },
        revoke: { _, _ in },
        validToken: { _, _ in throw CancellationError() },
        tokenHealth: { _ in .healthy },
        sweepExpiring: { _ in }
    )

    static let testValue = OAuthService(
        authorize: { _ in throw CancellationError() },
        refresh: { _, _ in throw CancellationError() },
        revoke: { _, _ in },
        validToken: { _, _ in throw CancellationError() },
        tokenHealth: { _ in .healthy },
        sweepExpiring: { _ in }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var oauthService: OAuthService {
        get { self[OAuthService.self] }
        set { self[OAuthService.self] = newValue }
    }
}

// MARK: - Live factory

extension OAuthService {
    /// Constructs the live client with its dependencies injected.
    /// Called by AppDependencyContainer — never by reducers or views.
    static func live(
        keychain: KeychainService,
        calendarContext: CalendarContext
    ) -> OAuthService {
        let coordinator = AuthSessionCoordinator()
        let refreshCoordinator = TokenRefreshCoordinator(
            keychain: keychain,
            calendarContext: calendarContext
        )

        return OAuthService(
            authorize: { config in
                try await coordinator.authorize(
                    config: config,
                    keychain: keychain,
                    cal: calendarContext
                )
            },
            refresh: { config, accountID in
                try await refreshCoordinator.refresh(config: config, accountID: accountID)
            },
            revoke: { config, accountID in
                try await _revoke(
                    config: config,
                    accountID: accountID,
                    keychain: keychain
                )
            },
            validToken: { config, accountID in
                try await _validToken(
                    config: config,
                    accountID: accountID,
                    keychain: keychain,
                    cal: calendarContext,
                    refreshCoordinator: refreshCoordinator
                )
            },
            tokenHealth: { accountID in
                _tokenHealth(
                    accountID: accountID,
                    keychain: keychain,
                    cal: calendarContext
                )
            },
            sweepExpiring: { threshold in
                await _sweepExpiring(
                    threshold: threshold,
                    keychain: keychain,
                    cal: calendarContext,
                    refreshCoordinator: refreshCoordinator
                )
            }
        )
    }
}

// MARK: - Auth Session Coordinator

/// Owns the ASWebAuthenticationSession lifecycle.
/// Retains the session to prevent deallocation before callback fires.
///
@MainActor
private final class AuthSessionCoordinator {
    private var retainedSession: ASWebAuthenticationSession?

    func authorize(
        config: OAuthProviderConfig,
        keychain: KeychainService,
        cal: CalendarContext
    ) async throws -> IntegrationAccount {
        let verifier = PKCEEngine.generateVerifier()
        let state = UUID().uuidString

        guard let authURL = PKCEEngine.buildAuthorizationURL(
            config: config,
            verifier: verifier,
            state: state
        ) else {
            throw OAuthError.invalidAuthorizationURL
        }

        let callbackURL = try await presentAuthSession(
            url: authURL,
            scheme: config.callbackURLScheme
        )

        guard let parsed = PKCEEngine.parseCallback(callbackURL) else {
            throw OAuthError.noCodeInCallback
        }
        guard parsed.state == state else {
            throw OAuthError.stateMismatch
        }

        let parseResult = try await exchangeCode(
            config: config,
            code: parsed.code,
            verifier: verifier,
            cal: cal
        )

        // Display name: use the token response if it provided one (Slack),
        // otherwise fetch via provider-specific API call.
        let displayName: String
        if let responseDisplayName = parseResult.displayName {
            displayName = responseDisplayName
        } else {
            displayName = (try? await config.fetchDisplayName(parseResult.token.accessToken))
                ?? config.provider.rawValue
        }

        let account = IntegrationAccount(
            provider: config.provider,
            displayName: displayName,
            token: parseResult.token,
            connectedAt: cal.now()
        )

        try keychain.save(account)
        log.info("Authorized \(config.provider.rawValue) account \(account.id)")

        return account
    }

    private func presentAuthSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { [weak self] callbackURL, error in
                self?.retainedSession = nil
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.browserCancelled)
                } else if let error {
                    continuation.resume(throwing: OAuthError.browserFailed(error))
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthError.noCallback)
                }
            }
            self.retainedSession = session
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

// MARK: - Code Exchange

private func exchangeCode(
    config: OAuthProviderConfig,
    code: String,
    verifier: String,
    cal: CalendarContext
) async throws -> TokenParseResult {
    var request = URLRequest(url: config.tokenURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = PKCEEngine.buildTokenExchangeBody(
        config: config,
        code: code,
        verifier: verifier
    )

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw OAuthError.codeExchangeFailed(statusCode: 0, body: "No HTTP response")
    }
    guard httpResponse.statusCode == 200 else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw OAuthError.codeExchangeFailed(
            statusCode: httpResponse.statusCode,
            body: body
        )
    }

    return try config.parseTokenResponse(data, cal)
}

// MARK: - Refresh

private func performRefresh(
    config: OAuthProviderConfig,
    refreshToken: String,
    cal: CalendarContext
) async throws -> OAuthToken {
    var request = URLRequest(url: config.tokenURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = PKCEEngine.buildRefreshBody(
        config: config,
        refreshToken: refreshToken
    )

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw OAuthError.refreshFailed(statusCode: 0, body: "No HTTP response")
    }

    if httpResponse.statusCode == 401 {
        throw OAuthError.reauthorizationRequired
    }

    guard httpResponse.statusCode == 200 else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw OAuthError.refreshFailed(
            statusCode: httpResponse.statusCode,
            body: body
        )
    }

    return try config.parseTokenResponse(data, cal).token
}

// MARK: - Revoke

private func _revoke(
    config: OAuthProviderConfig,
    accountID: UUID,
    keychain: KeychainService
) async throws {
    if let revokeURL = config.revokeURL,
       let account = try keychain.account(accountID) {
        let tokenEncoded = account.token.accessToken
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account.token.accessToken
        let clientEncoded = config.clientID
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.clientID

        var request = URLRequest(url: revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(tokenEncoded)&client_id=\(clientEncoded)".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    try keychain.delete(accountID)
    log.info("Revoked \(config.provider.rawValue) account \(accountID)")
}

// MARK: - Valid Token

private func _validToken(
    config: OAuthProviderConfig,
    accountID: UUID,
    keychain: KeychainService,
    cal: CalendarContext,
    refreshCoordinator: TokenRefreshCoordinator
) async throws -> OAuthToken {
    guard let account = try keychain.account(accountID) else {
        throw OAuthError.noAccount
    }

    let isExpired = account.token.expiresAt.map { cal.now() >= $0 } ?? false

    if isExpired {
        return try await refreshCoordinator.refresh(config: config, accountID: accountID)
    }

    return account.token
}

// MARK: - Token Health

private func _tokenHealth(
    accountID: UUID,
    keychain: KeychainService,
    cal: CalendarContext
) -> TokenHealth {
    guard let account = try? keychain.account(accountID) else {
        return .reconnectRequired
    }

    guard let expiresAt = account.token.expiresAt else {
        return .healthy
    }

    let now = cal.now()
    if now >= expiresAt {
        return account.token.refreshToken != nil ? .expired : .reconnectRequired
    }
    if expiresAt.timeIntervalSince(now) < expiringSoonThreshold {
        return .expiringSoon
    }
    return .healthy
}

// MARK: - Sweep

private func _sweepExpiring(
    threshold: TimeInterval,
    keychain: KeychainService,
    cal: CalendarContext,
    refreshCoordinator: TokenRefreshCoordinator
) async {
    guard let accounts = try? keychain.allAccounts() else { return }

    let now = cal.now()
    for account in accounts {
        guard let expiresAt = account.token.expiresAt,
              expiresAt.timeIntervalSince(now) < threshold,
              account.token.refreshToken != nil
        else { continue }

        let config = OAuthProviderConfig.config(for: account.provider)
        do {
            _ = try await refreshCoordinator.refresh(config: config, accountID: account.id)
            log.info("Sweep refreshed \(account.provider.rawValue) \(account.id)")
        } catch {
            log.error("Sweep refresh failed \(account.provider.rawValue): \(error)")
        }
    }
}

// MARK: - Refresh Coordinator (serialization per account)

/// Ensures only one refresh is in-flight per account at a time.
/// Subsequent callers await the in-flight result rather than
/// issuing duplicate refresh requests.
///
/// Check-and-insert is atomic within a single `withValue` call.
///
private final class TokenRefreshCoordinator: Sendable {
    private let inFlight = LockIsolated<[UUID: Task<OAuthToken, any Error>]>([:])
    private let keychain: KeychainService
    private let calendarContext: CalendarContext

    init(keychain: KeychainService, calendarContext: CalendarContext) {
        self.keychain = keychain
        self.calendarContext = calendarContext
    }

    func refresh(config: OAuthProviderConfig, accountID: UUID) async throws -> OAuthToken {
        let keychain = self.keychain
        let cal = self.calendarContext

        // Atomic check-and-insert: either return an existing in-flight task
        // or create and store a new one in a single `withValue` call.
        let task: Task<OAuthToken, any Error> = inFlight.withValue { map in
            if let existing = map[accountID] {
                return existing
            }

            let newTask = Task<OAuthToken, any Error> {
                defer { self.inFlight.withValue { $0[accountID] = nil } }

                guard let account = try keychain.account(accountID) else {
                    throw OAuthError.noAccount
                }
                guard let existingRefreshToken = account.token.refreshToken else {
                    throw OAuthError.reauthorizationRequired
                }

                let newToken = try await performRefresh(
                    config: config,
                    refreshToken: existingRefreshToken,
                    cal: cal
                )

                let updatedAccount = IntegrationAccount(
                    id: account.id,
                    provider: account.provider,
                    displayName: account.displayName,
                    token: newToken,
                    connectedAt: account.connectedAt
                )
                try keychain.save(updatedAccount)

                log.info("Refreshed \(config.provider.rawValue) account \(accountID)")
                return newToken
            }

            map[accountID] = newTask
            return newTask
        }

        return try await task.value
    }
}
