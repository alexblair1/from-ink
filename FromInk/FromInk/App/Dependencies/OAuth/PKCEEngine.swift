import CryptoKit
import Foundation
import Security

/// Stateless PKCE cryptographic operations. Pure functions, no side effects.
/// See RFC 7636 for the PKCE specification.
///
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
    /// Returns nil if the URL cannot be constructed.
    static func buildAuthorizationURL(
        config: OAuthProviderConfig,
        verifier: String,
        state: String
    ) -> URL? {
        guard var components = URLComponents(
            url: config.authorizeURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: config.scopeParameterName, value: config.scopeString),
            URLQueryItem(name: "code_challenge", value: generateChallenge(from: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url
    }

    /// Build the token exchange request body.
    static func buildTokenExchangeBody(
        config: OAuthProviderConfig,
        code: String,
        verifier: String
    ) -> Data {
        let params = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier,
        ]
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    /// Build the token refresh request body.
    static func buildRefreshBody(
        config: OAuthProviderConfig,
        refreshToken: String
    ) -> Data {
        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ]
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    /// Extract the authorization code and state from a callback URL.
    static func parseCallback(_ url: URL) -> (code: String, state: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            return nil
        }
        return (code, state)
    }
}

// MARK: - Base64URL

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
