import Foundation

/// State machine for a single provider connection.
/// Used by IntegrationFeature (future) to track auth lifecycle.
///
enum AuthConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(IntegrationAccount)
    case refreshing(IntegrationAccount)
    case reconnectRequired
    case failed(String)
}
