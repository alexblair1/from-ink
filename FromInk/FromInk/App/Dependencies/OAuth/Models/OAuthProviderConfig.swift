import Foundation

/// Static configuration for a PKCE OAuth provider.
/// Every integration is described by data, not code — the PKCE flow
/// is identical for all providers. Provider-specific differences
/// (scope parameter name, token response shape, display name fetching)
/// are expressed as closures on the config.
///
struct OAuthProviderConfig: Sendable {
    let provider: OAuthProvider
    let clientID: String
    let authorizeURL: URL
    let tokenURL: URL
    let revokeURL: URL?
    let scopes: [String]
    let scopeSeparator: String
    let scopeParameterName: String
    let callbackURLScheme: String
    let redirectPath: String

    /// Parses the token endpoint response into an OAuthToken.
    /// Provider-specific because Slack nests tokens under `authed_user`.
    let parseTokenResponse: @Sendable (Data, CalendarContext) throws -> TokenParseResult

    /// Fetches a human-readable display name after authorization.
    /// Called with the new access token. Returns the display name string.
    let fetchDisplayName: @Sendable (String) async throws -> String

    var redirectURI: String {
        "\(callbackURLScheme)://\(redirectPath)"
    }

    var scopeString: String {
        scopes.joined(separator: scopeSeparator)
    }
}

/// Token parse result — includes the token plus any provider-specific
/// extras extracted from the response (e.g. Slack's team name).
///
struct TokenParseResult: Sendable {
    let token: OAuthToken
    let displayName: String?
}

// MARK: - Standard token parser (Linear and RFC-compliant providers)

private func standardTokenParser(data: Data, cal: CalendarContext) throws -> TokenParseResult {
    struct Response: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        let token_type: String?
        let scope: String?
    }

    let response = try JSONDecoder().decode(Response.self, from: data)
    let expiresAt = response.expires_in.map {
        cal.now().addingTimeInterval(TimeInterval($0))
    }

    return TokenParseResult(
        token: OAuthToken(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: expiresAt,
            tokenType: response.token_type ?? "Bearer",
            scope: response.scope
        ),
        displayName: nil
    )
}

// MARK: - Slack token parser

private func slackTokenParser(data: Data, cal: CalendarContext) throws -> TokenParseResult {
    struct Response: Decodable {
        let ok: Bool
        let authed_user: AuthedUser?
        let team: Team?
        let error: String?

        struct AuthedUser: Decodable {
            let id: String
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let token_type: String?
            let scope: String?
        }

        struct Team: Decodable {
            let id: String?
            let name: String?
        }
    }

    let response = try JSONDecoder().decode(Response.self, from: data)

    guard response.ok, let user = response.authed_user else {
        let errorMessage = response.error ?? "Unknown Slack error"
        throw OAuthError.codeExchangeFailed(statusCode: 200, body: errorMessage)
    }

    let expiresAt = user.expires_in.map {
        cal.now().addingTimeInterval(TimeInterval($0))
    }

    let displayName = [response.team?.name, user.id]
        .compactMap { $0 }
        .joined(separator: " — ")

    return TokenParseResult(
        token: OAuthToken(
            accessToken: user.access_token,
            refreshToken: user.refresh_token,
            expiresAt: expiresAt,
            tokenType: user.token_type ?? "user",
            scope: user.scope
        ),
        displayName: displayName.isEmpty ? nil : displayName
    )
}

// MARK: - Display name fetchers

private func linearFetchDisplayName(accessToken: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = #"{"query":"{ viewer { name email } }"}"#.data(using: .utf8)

    let (data, _) = try await URLSession.shared.data(for: request)

    struct Response: Decodable {
        let data: ViewerData?
        struct ViewerData: Decodable {
            let viewer: Viewer
            struct Viewer: Decodable {
                let name: String
                let email: String
            }
        }
    }

    let response = try JSONDecoder().decode(Response.self, from: data)
    if let viewer = response.data?.viewer {
        return "\(viewer.name) (\(viewer.email))"
    }
    return "Linear"
}

private func slackFetchDisplayName(accessToken: String) async throws -> String {
    // Slack display name is extracted from the token response directly
    // via TokenParseResult.displayName. This is a fallback.
    return "Slack"
}

// MARK: - Provider configs

extension OAuthProviderConfig {
    static let linear = OAuthProviderConfig(
        provider: .linear,
        clientID: "/* registered at linear.app/settings/api */",
        authorizeURL: URL(string: "https://linear.app/oauth/authorize")!,
        tokenURL: URL(string: "https://api.linear.app/oauth/token")!,
        revokeURL: URL(string: "https://api.linear.app/oauth/revoke")!,
        scopes: ["read", "write", "issues:create"],
        scopeSeparator: ",",
        scopeParameterName: "scope",
        callbackURLScheme: "fromink",
        redirectPath: "oauth/linear",
        parseTokenResponse: standardTokenParser,
        fetchDisplayName: linearFetchDisplayName
    )

    static let slack = OAuthProviderConfig(
        provider: .slack,
        clientID: "/* registered at api.slack.com/apps */",
        authorizeURL: URL(string: "https://slack.com/oauth/v2/authorize")!,
        tokenURL: URL(string: "https://slack.com/api/oauth.v2.access")!,
        revokeURL: URL(string: "https://slack.com/api/auth.revoke")!,
        scopes: ["chat:write", "channels:read", "users:read"],
        scopeSeparator: ",",
        scopeParameterName: "user_scope",
        callbackURLScheme: "fromink",
        redirectPath: "oauth/slack",
        parseTokenResponse: slackTokenParser,
        fetchDisplayName: slackFetchDisplayName
    )

    static func config(for provider: OAuthProvider) -> OAuthProviderConfig {
        switch provider {
        case .linear: return .linear
        case .slack:  return .slack
        }
    }
}
