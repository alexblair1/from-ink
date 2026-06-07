import Foundation
import AVFoundation

/// Sendable, framework-neutral mirror of `AVAudioApplication.recordPermission`.
/// Lives at the same level as `PermissionAuthStatus` (the EventKit
/// equivalent) so TCA reducers can express microphone authorization
/// without depending on `AVFoundation`'s `@objc` enum.
///
/// Microphone access is a two-state grant — no `restricted` or
/// `writeOnly` equivalent like calendar / reminders. The system either
/// allows the app to record or it does not.
///
enum MicrophoneAuthStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    init(_ status: AVAudioApplication.recordPermission) {
        switch status {
        case .undetermined: self = .notDetermined
        case .denied:       self = .denied
        case .granted:      self = .granted
        @unknown default:   self = .notDetermined
        }
    }

    /// True iff the app can record audio. Drives the visual on-state of
    /// the microphone permission affordance.
    var grantsAccess: Bool { self == .granted }

    /// True iff the user must go to Settings to change the state. For
    /// microphone that's only `.denied` — `.granted` is reversible too
    /// (via Settings) but the affordance treats it as "done".
    var requiresSettings: Bool { self == .denied }
}
