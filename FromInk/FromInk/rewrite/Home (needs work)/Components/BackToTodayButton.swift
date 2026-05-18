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
                // `arrow.backward` is the direction-aware "previous" symbol
                // — it auto-flips for right-to-left layouts (Arabic, Hebrew,
                // Persian, Urdu). `arrow.left` stays pointing left in RTL
                // and breaks the "going back in time" semantic.
                Image(systemName: "arrow.backward")
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    // Graceful scaling for verbose localizations
                    // ("AUJOURD'HUI" 11ch French, "СЕГОДНЯ" 7ch Russian) on
                    // narrow viewports. The text shrinks to ~7pt before the
                    // masthead is forced to wrap. allowsTightening tightens
                    // kerning slightly before scaling to gain a couple
                    // pixels without visibly shrinking the glyphs.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
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
        // Layout priority < default (0) so when the masthead and this
        // button compete for horizontal space in their parent HStack,
        // this button yields first — its text scales down via
        // minimumScaleFactor rather than forcing the masthead's date to
        // wrap or shrink. The masthead is the primary editorial element;
        // the back-to-today button is the secondary affordance.
        .layoutPriority(-1)
    }
}
