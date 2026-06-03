import SwiftUI

/// Leading-edge indicator for events currently in progress. A 3pt
/// vertical bar that gently pulses while active; invisible (but space-
/// reserving) when inactive so layout stays stable across state
/// changes.
///
/// **View-tree branching.** Active and inactive states are *separate
/// subtrees* — `PulsingBar` (the animated rectangle) vs `Color.clear`.
/// SwiftUI destroys the subtree when its branch is no longer taken,
/// which cleanly tears down the `.repeatForever(autoreverses:)`
/// animation and its `@State`. Without this, an active `.animation(
/// _:value:)` modifier can race the new opacity target after `isActive`
/// flips false, producing visible "rapid blinking" at the transition
/// while the animation engine reconciles two competing targets.
///
/// **Accessibility.** Honors `accessibilityReduceMotion`: when reduce-
/// motion is on, the bar paints at a fixed 0.6 opacity (still visible,
/// no animation). Apple HIG requirement — and the same fallback we
/// already applied to the Time Warp wheel's custom transitions.
///
struct InProgressBar: View {
    let isActive: Bool
    let color: Color
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isActive {
                if reduceMotion {
                    Rectangle()
                        .fill(color)
                        .opacity(0.6)
                } else {
                    PulsingBar(color: color)
                }
            } else {
                Color.clear
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// The animated leaf. Owns its own `@State` for the pulse phase so the
/// entire subtree (state + animation) is created and destroyed by the
/// parent's `if isActive` branch — no lingering animation when the
/// event ends.
private struct PulsingBar: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Rectangle()
            .fill(color)
            .opacity(pulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
