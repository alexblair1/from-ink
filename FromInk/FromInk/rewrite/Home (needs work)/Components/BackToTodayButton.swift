import SwiftUI

/// Small mono-styled button shown beside the masthead date when the user has
/// warped to a non-today day. Tapping warps back to today.
///
/// Visual: `← TODAY` in SF Mono uppercase, 1pt ink border, no fill.
/// Matches the React design's "← TODAY" affordance from `time-warp.jsx`.
///
struct BackToTodayButton: View {
    let label: String
    let action: () -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .textCase(.uppercase)
            }
            .foregroundStyle(ds.colors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                Rectangle()
                    .stroke(ds.colors.ink, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
