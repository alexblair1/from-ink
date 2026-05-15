import Foundation

/// Errors from the PKCE OAuth flow.
/// Manual Equatable because `browserFailed` wraps `any Error`.
///
enum OAuthError: Error {
    case stateMismatch
    case browserFailed(any Error)
    case browserCancelled
    case noCallback
    case noCodeInCallback
    case invalidAuthorizationURL
    case codeExchangeFailed(statusCode: Int, body: String)
    case refreshFailed(statusCode: Int, body: String)
    case reauthorizationRequired
    case noAccount
    case keychainError(OSStatus)
}

extension OAuthError: Equatable {
    static func == (lhs: OAuthError, rhs: OAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.stateMismatch, .stateMismatch),
             (.browserCancelled, .browserCancelled),
             (.noCallback, .noCallback),
             (.noCodeInCallback, .noCodeInCallback),
             (.invalidAuthorizationURL, .invalidAuthorizationURL),
             (.reauthorizationRequired, .reauthorizationRequired),
             (.noAccount, .noAccount):
            return true
        case (.browserFailed, .browserFailed):
            return true
        case (.codeExchangeFailed(let a, _), .codeExchangeFailed(let b, _)):
            return a == b
        case (.refreshFailed(let a, _), .refreshFailed(let b, _)):
            return a == b
        case (.keychainError(let a), .keychainError(let b)):
            return a == b
        default:
            return false
        }
    }
}
