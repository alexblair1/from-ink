import Foundation
import CoreLocation

/// Sendable, framework-neutral mirror of `CLAuthorizationStatus`. Lives
/// at the same level as `PermissionAuthStatus` (EventKit) and
/// `MicrophoneAuthStatus` (AVAudioApplication) so TCA reducers can
/// express location authorization without depending on CoreLocation's
/// `@objc` enum.
///
/// `.authorizedAlways` and `.authorizedWhenInUse` collapse into a
/// single `.authorized` because the brief / weather use case only ever
/// reads location while the app is in the foreground. The distinction
/// between the two CoreLocation states isn't load-bearing for us.
///
enum LocationAuthStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        case .authorizedAlways, .authorizedWhenInUse: self = .authorized
        @unknown default:    self = .notDetermined
        }
    }

    /// True iff the brief's weather widget can read a location.
    var grantsAccess: Bool { self == .authorized }

    /// True iff the user must go to Settings to change this status —
    /// `.notDetermined` doesn't qualify because we can still prompt
    /// in-app. `.authorized` doesn't qualify either; we route there on
    /// tap anyway so users can revoke, but the affordance reads as the
    /// active toggle, not the explicit Settings handoff.
    var requiresSettings: Bool {
        switch self {
        case .notDetermined, .authorized: return false
        case .denied, .restricted:        return true
        }
    }
}
