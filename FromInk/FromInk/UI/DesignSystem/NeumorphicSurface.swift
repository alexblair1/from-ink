import SwiftUI

/// Reusable "stamped paper" surface treatment used by the brief tabs and
/// any future component that wants the same neumorphic affordance (cards,
/// buttons, toggles, etc.).
///
/// The metaphor: paper that can be raised slightly (default resting state)
/// or pressed into the page (active / selected state). Both states use
/// extremely subtle shadow work — the system reads as physical without
/// ever looking glossy.
///
/// Light + dark variants follow the spec from `Notebook Tabs - Dark Mode`:
/// - **Light raise** = white highlight on top + faint ink edges all around.
/// - **Dark raise** = inset cream highlight on top only (outset shadows
///   render as visible hairlines on dark paper).
/// - **Light press** = inset ink shadow at 5-7% alpha on top/L/R; the
///   bottom stays clean so the surface bleeds into the panel below.
/// - **Dark press** = inset pure-black at 35-55% alpha — dark-on-dark
///   needs ~8× the alpha to perceive the same depth.
///
/// Inset shadows are synthesized via gradient overlays because SwiftUI
/// has no `inset box-shadow` primitive. The approximation reads close to
/// the CSS spec at common cell sizes.
///
extension View {
    /// Resting state — paper sits slightly above the page.
    func neumorphicRaised() -> some View {
        modifier(NeumorphicRaisedModifier())
    }

    /// Active / selected state — paper pressed into the page on the top
    /// and side edges. The bottom intentionally has no inset so the
    /// surface bleeds into whatever sits beneath it (the panel pattern).
    func neumorphicPressed() -> some View {
        modifier(NeumorphicPressedModifier())
    }
}

// MARK: - Raised

struct NeumorphicRaisedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        switch colorScheme {
        case .dark:
            content.overlay(alignment: .top) {
                // Warm cream highlight along the top edge — the paper
                // catching light. The only treatment in dark mode; outset
                // drop shadows render as visible hairlines on dark paper.
                Rectangle()
                    .fill(Color(white: 0.93).opacity(0.08))
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }

        default:
            // Light mode: composite of one white highlight on top + four
            // very faint ink shadows on all sides. The accumulated effect
            // is the "v3 Whisper" raise from the spec.
            content
                .shadow(color: .white.opacity(0.6),                 radius: 1, x: 0, y: -1)
                .shadow(color: Color(white: 0.12).opacity(0.02),    radius: 2, x: 0, y: -1)
                .shadow(color: Color(white: 0.12).opacity(0.03),    radius: 2, x: 0, y: 1)
                .shadow(color: Color(white: 0.12).opacity(0.02),    radius: 2, x: -1, y: 0)
                .shadow(color: Color(white: 0.12).opacity(0.02),    radius: 2, x: 1, y: 0)
        }
    }
}

// MARK: - Pressed

struct NeumorphicPressedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // Dialed-down from the React spec on device feedback — the spec
        // values (0.07 light / 0.55 dark) read too aggressive in the
        // SwiftUI gradient synthesis. Halved values still convey the
        // press without dominating the row beneath.
        let opacity = colorScheme == .dark ? 0.28 : 0.04
        let inkColor = Color(white: 0)

        content.overlay {
            // Inset shadows on top + left + right. Bottom intentionally
            // omitted so the surface bleeds into whatever sits beneath.
            //
            // Gradient lengths hug the edges tightly — extending the
            // fade further into the interior made the shadow read as a
            // vignette rather than an inset. A real CSS inset shadow
            // attenuates with a tight blur radius; we mirror that by
            // ending the gradient close to the edge.
            ZStack {
                // Top — 7% of height
                LinearGradient(
                    colors: [inkColor.opacity(opacity), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.07)
                )

                // Left — 2.5% of width (top was fine at 7%; the sides
                // were still bleeding too far into the cell)
                LinearGradient(
                    colors: [inkColor.opacity(opacity * 0.6), .clear],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.025, y: 0.5)
                )

                // Right — 2.5% of width
                LinearGradient(
                    colors: [.clear, inkColor.opacity(opacity * 0.6)],
                    startPoint: UnitPoint(x: 0.975, y: 0.5),
                    endPoint: .trailing
                )
            }
            .allowsHitTesting(false)
        }
    }
}
