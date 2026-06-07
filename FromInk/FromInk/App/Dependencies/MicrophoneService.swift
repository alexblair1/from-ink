import AVFoundation
import ComposableArchitecture

/// TCA dependency client for microphone permission. Mirrors the read /
/// request shape of `EventKitService`'s permission entry points so the
/// onboarding permissions reducer can treat all three permissions
/// (calendar, reminders, microphone) with the same surface.
///
/// `status()` is async because `AVAudioApplication.shared` is main-actor
/// isolated under Swift 6 strict concurrency. Wrapping the read in
/// `MainActor.run` is the smallest concession that keeps the closure
/// `@Sendable`.
///
struct MicrophoneService: Sendable {
    /// Current authorization state, read synchronously from
    /// `AVAudioApplication.shared.recordPermission`.
    var status: @Sendable () async -> MicrophoneAuthStatus
    /// Presents the system microphone permission prompt if the status is
    /// `.notDetermined`. Resolves to the post-prompt status.
    var requestAccess: @Sendable () async -> MicrophoneAuthStatus
}

extension MicrophoneService: DependencyKey {
    static var liveValue: MicrophoneService {
        MicrophoneService(
            status: {
                await MainActor.run {
                    MicrophoneAuthStatus(AVAudioApplication.shared.recordPermission)
                }
            },
            requestAccess: {
                _ = await AVAudioApplication.requestRecordPermission()
                return await MainActor.run {
                    MicrophoneAuthStatus(AVAudioApplication.shared.recordPermission)
                }
            }
        )
    }

    static var testValue: MicrophoneService {
        MicrophoneService(
            status: { .notDetermined },
            requestAccess: { .notDetermined }
        )
    }
}

extension DependencyValues {
    var microphoneService: MicrophoneService {
        get { self[MicrophoneService.self] }
        set { self[MicrophoneService.self] = newValue }
    }
}
