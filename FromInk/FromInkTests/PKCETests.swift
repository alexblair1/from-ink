import ComposableArchitecture
import CryptoKit
import XCTest
@testable import FromInk

final class PKCEEngineTests: XCTestCase {

    // MARK: - Verifier

    func test_verifier_is43CharactersBase64URL() {
        let verifier = PKCEEngine.generateVerifier()
        // 32 bytes → 43 base64url characters (no padding)
        XCTAssertEqual(verifier.count, 43)
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))
    }

    func test_verifier_isUnique() {
        let a = PKCEEngine.generateVerifier()
        let b = PKCEEngine.generateVerifier()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Challenge

    func test_challenge_isSHA256OfVerifier() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCEEngine.generateChallenge(from: verifier)

        // Verify independently
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertEqual(challenge, expected)
    }

    func test_challenge_isDeterministic() {
        let verifier = PKCEEngine.generateVerifier()
        let a = PKCEEngine.generateChallenge(from: verifier)
        let b = PKCEEngine.generateChallenge(from: verifier)
        XCTAssertEqual(a, b)
    }

    // MARK: - Authorization URL

    func test_buildAuthorizationURL_containsRequiredParams() {
        let config = OAuthProviderConfig.linear
        let verifier = "test-verifier-value"
        let state = "test-state-value"

        let url = PKCEEngine.buildAuthorizationURL(
            config: config,
            verifier: verifier,
            state: state
        )

        XCTAssertNotNil(url)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let params = Dictionary(
            queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            },
            uniquingKeysWith: { _, last in last }
        )

        XCTAssertEqual(params["client_id"], config.clientID)
        XCTAssertEqual(params["redirect_uri"], config.redirectURI)
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["state"], state)
        XCTAssertNotNil(params["code_challenge"])
        XCTAssertNotNil(params["scope"])
    }

    func test_buildAuthorizationURL_challengeMatchesVerifier() {
        let verifier = "test-verifier"
        let url = PKCEEngine.buildAuthorizationURL(
            config: .linear,
            verifier: verifier,
            state: "s"
        )!

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let challenge = components.queryItems?.first { $0.name == "code_challenge" }?.value

        XCTAssertEqual(challenge, PKCEEngine.generateChallenge(from: verifier))
    }

    // MARK: - Callback Parsing

    func test_parseCallback_extractsCodeAndState() {
        let url = URL(string: "fromink://oauth/linear?code=abc123&state=xyz789")!
        let result = PKCEEngine.parseCallback(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.code, "abc123")
        XCTAssertEqual(result?.state, "xyz789")
    }

    func test_parseCallback_returnsNilForMissingCode() {
        let url = URL(string: "fromink://oauth/linear?state=xyz789")!
        XCTAssertNil(PKCEEngine.parseCallback(url))
    }

    func test_parseCallback_returnsNilForMissingState() {
        let url = URL(string: "fromink://oauth/linear?code=abc123")!
        XCTAssertNil(PKCEEngine.parseCallback(url))
    }

    // MARK: - Token Exchange Body

    func test_tokenExchangeBody_containsRequiredFields() {
        let body = PKCEEngine.buildTokenExchangeBody(
            config: .linear,
            code: "auth-code",
            verifier: "test-verifier"
        )

        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("grant_type=authorization_code"))
        XCTAssertTrue(bodyString.contains("code=auth-code"))
        XCTAssertTrue(bodyString.contains("code_verifier=test-verifier"))
        XCTAssertTrue(bodyString.contains("client_id="))
        XCTAssertTrue(bodyString.contains("redirect_uri="))
    }

    // MARK: - Refresh Body

    func test_refreshBody_containsRequiredFields() {
        let body = PKCEEngine.buildRefreshBody(
            config: .linear,
            refreshToken: "refresh-token-123"
        )

        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("grant_type=refresh_token"))
        XCTAssertTrue(bodyString.contains("refresh_token=refresh-token-123"))
        XCTAssertTrue(bodyString.contains("client_id="))
    }
}

// MARK: - KeychainService Tests

final class KeychainServiceTests: XCTestCase {

    private func makeKeychain() -> KeychainService {
        let storage = LockIsolated<[UUID: IntegrationAccount]>([:])
        return KeychainService(
            save: { account in storage.withValue { $0[account.id] = account } },
            accounts: { provider in storage.withValue { $0.values.filter { $0.provider == provider } } },
            account: { id in storage.withValue { $0[id] } },
            allAccounts: { storage.withValue { Array($0.values) } },
            delete: { id in storage.withValue { $0[id] = nil } }
        )
    }

    func test_saveAndLoad_roundTrips() throws {
        let keychain = makeKeychain()
        let account = IntegrationAccount(
            provider: .linear,
            displayName: "Test Workspace",
            token: OAuthToken(
                accessToken: "access-123",
                refreshToken: "refresh-456",
                expiresAt: Date(timeIntervalSince1970: 1_778_673_600),
                tokenType: "Bearer",
                scope: "read write"
            ),
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        )

        try keychain.save(account)
        let loaded = try keychain.accounts(.linear)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, account.id)
        XCTAssertEqual(loaded[0].displayName, "Test Workspace")
        XCTAssertEqual(loaded[0].token.accessToken, "access-123")
    }

    func test_accountByID() throws {
        let keychain = makeKeychain()
        let account = IntegrationAccount(
            provider: .slack,
            displayName: "alexblair",
            token: OAuthToken(
                accessToken: "gh-token",
                refreshToken: nil,
                expiresAt: nil,
                tokenType: "Bearer",
                scope: "repo"
            ),
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        )

        try keychain.save(account)
        let found = try keychain.account(account.id)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.provider, .slack)
    }

    func test_delete_removesAccount() throws {
        let keychain = makeKeychain()
        let account = IntegrationAccount(
            provider: .slack,
            displayName: "Workspace",
            token: OAuthToken(
                accessToken: "sl-token",
                refreshToken: "sl-refresh",
                expiresAt: nil,
                tokenType: "Bearer",
                scope: nil
            ),
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        )

        try keychain.save(account)
        try keychain.delete(account.id)
        let found = try keychain.account(account.id)

        XCTAssertNil(found)
    }

    func test_accounts_filtersProvider() throws {
        let keychain = makeKeychain()
        let token = OAuthToken(
            accessToken: "t",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer",
            scope: nil
        )

        try keychain.save(IntegrationAccount(
            provider: .linear,
            displayName: "Linear",
            token: token,
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        ))
        try keychain.save(IntegrationAccount(
            provider: .slack,
            displayName: "Slack",
            token: token,
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        ))

        let linearAccounts = try keychain.accounts(.linear)
        let slackAccounts = try keychain.accounts(.slack)

        XCTAssertEqual(linearAccounts.count, 1)
        XCTAssertEqual(slackAccounts.count, 1)
    }

    func test_allAccounts_returnsAll() throws {
        let keychain = makeKeychain()
        let token = OAuthToken(
            accessToken: "t",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer",
            scope: nil
        )

        try keychain.save(IntegrationAccount(
            provider: .linear,
            displayName: "L",
            token: token,
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        ))
        try keychain.save(IntegrationAccount(
            provider: .slack,
            displayName: "G",
            token: token,
            connectedAt: Date(timeIntervalSince1970: 1_778_673_600)
        ))

        let all = try keychain.allAccounts()
        XCTAssertEqual(all.count, 2)
    }
}

// MARK: - OAuthError Tests

final class OAuthErrorTests: XCTestCase {

    func test_equatable_sameCase() {
        XCTAssertEqual(OAuthError.stateMismatch, OAuthError.stateMismatch)
        XCTAssertEqual(OAuthError.noCallback, OAuthError.noCallback)
        XCTAssertEqual(OAuthError.reauthorizationRequired, OAuthError.reauthorizationRequired)
    }

    func test_equatable_differentCases() {
        XCTAssertNotEqual(OAuthError.stateMismatch, OAuthError.noCallback)
    }

    func test_equatable_codeExchangeFailed_matchesOnStatusCode() {
        XCTAssertEqual(
            OAuthError.codeExchangeFailed(statusCode: 400, body: "bad"),
            OAuthError.codeExchangeFailed(statusCode: 400, body: "different")
        )
        XCTAssertNotEqual(
            OAuthError.codeExchangeFailed(statusCode: 400, body: ""),
            OAuthError.codeExchangeFailed(statusCode: 401, body: "")
        )
    }

    func test_equatable_keychainError_matchesOnStatus() {
        XCTAssertEqual(
            OAuthError.keychainError(-25300),
            OAuthError.keychainError(-25300)
        )
        XCTAssertNotEqual(
            OAuthError.keychainError(-25300),
            OAuthError.keychainError(-25299)
        )
    }
}

// MARK: - OAuthProviderConfig Tests

final class OAuthProviderConfigTests: XCTestCase {

    func test_allProviders_haveConfigs() {
        for provider in OAuthProvider.allCases {
            let config = OAuthProviderConfig.config(for: provider)
            XCTAssertEqual(config.provider, provider)
            XCTAssertEqual(config.callbackURLScheme, "fromink")
            XCTAssertTrue(config.redirectPath.hasPrefix("oauth/"))
        }
    }

    func test_redirectURI_format() {
        let config = OAuthProviderConfig.linear
        XCTAssertEqual(config.redirectURI, "fromink://oauth/linear")
    }
}
