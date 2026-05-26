import Foundation
import EventKit

/// Sendable, framework-neutral mirror of `EKAuthorizationStatus`. Used by
/// the TCA permissions surface so reducers don't depend on EventKit's
/// `@objc` enum (which isn't `Sendable`).
///
/// iOS 17+ split the legacy `.authorized` case into `.fullAccess` (read +
/// write, which we need for the daily brief / dispatch panel) and
/// `.writeOnly` (event creation only — users can still route tasks to
/// Calendar but the brief can't surface their existing events).
enum PermissionAuthStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    /// Write-only access (iOS 17+ EventKit). Calendar/reminder creation
    /// works; reads don't. The brief degrades to "no events today" but
    /// task routing to Calendar still works.
    case writeOnly
    /// Full read + write access — the only state where the brief shows
    /// the user's real calendar.
    case fullAccess

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        case .writeOnly:     self = .writeOnly
        case .fullAccess:    self = .fullAccess
        @unknown default:    self = .notDetermined
        }
    }

    /// True iff our read paths (events/reminders fetch) will succeed.
    var grantsRead: Bool { self == .fullAccess }
}
