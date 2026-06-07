import Foundation

/// Ordered list of onboarding screens. Matches the Native Kit design.
///
/// - welcome: hero ink mark + "From Ink" wordmark
/// - value: "The idea" — three feature rows
/// - permissions: calendar + reminder toggles + microphone info card.
///   Swipe is disabled on this step — the user must tap a button.
/// - subscription: pricing card + checkmark feature list.
///   Either CTA on this step completes the flow.
///
enum OnboardingStep: String, Equatable, Hashable, CaseIterable, Sendable, Identifiable {
    case welcome
    case value
    case permissions
    case subscription

    var id: String { rawValue }

    /// The next step in the sequence, or `nil` if this is the last.
    var next: OnboardingStep? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}
