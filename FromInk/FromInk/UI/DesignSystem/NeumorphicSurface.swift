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
/// All shadow alphas, gradient stops, and highlight colors are tokens
/// on `DesignSystem.neumorphicElevation` — tuning the feel of the entire
/// system happens in one place (`NeumorphicTokens.swift`), not by editing
/// these modifiers.
///
/// Light + dark variants follow the spec from `Notebook Tabs - Dark Mode`:
/// - **Light raise** = white highlight on top + faint ink edges all around.
/// - **Dark raise** = inset cream highlight on top only (outset shadows
///   render as visible hairlines on dark paper).
/// - **Press (both themes)** = inset gradient on top + L + R; the bottom
///   stays clean so the surface bleeds into the panel below.
///
extension View {
    /// Resting state — paper sits slightly above the page.
    func neumorphicRaised(
        elevation: NeumorphicElevation = DesignSystem.standard.neumorphicElevation
    ) -> some View {
        modifier(NeumorphicRaisedModifier(elevation: elevation))
    }

    /// Active / selected state — paper pressed into the page on the top
    /// and side edges. The bottom intentionally has no inset so the
    /// surface bleeds into whatever sits beneath it (the panel pattern).
    func neumorphicPressed(
        elevation: NeumorphicElevation = DesignSystem.standard.neumorphicElevation
    ) -> some View {
        modifier(NeumorphicPressedModifier(elevation: elevation))
    }
}

// MARK: - Raised

struct NeumorphicRaisedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let elevation: NeumorphicElevation

    func body(content: Content) -> some View {
        switch colorScheme {
        case .dark:
            content.overlay(alignment: .top) {
                Rectangle()
                    .fill(elevation.darkRaiseHighlightColor)
                    .frame(height: elevation.darkRaiseHighlightHeight)
                    .allowsHitTesting(false)
            }

        default:
            // Light raise: stack the composite shadows from the token.
            // Each shadow modifier wraps the prior view; folding the array
            // applies them in order.
            elevation.lightRaiseShadows.reduce(AnyView(content)) { partial, spec in
                AnyView(
                    partial.shadow(
                        color: spec.color,
                        radius: spec.radius,
                        x: spec.x,
                        y: spec.y
                    )
                )
            }
        }
    }
}

// MARK: - Pressed

struct NeumorphicPressedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let elevation: NeumorphicElevation

    func body(content: Content) -> some View {
        let topAlpha = colorScheme == .dark
            ? elevation.darkPressTopAlpha
            : elevation.lightPressTopAlpha
        let sideAlpha = topAlpha * elevation.pressSideAlphaMultiplier
        let ink = elevation.pressInkColor

        content.overlay {
            // Inset shadows on top + left + right. Bottom intentionally
            // omitted so the surface bleeds into whatever sits beneath.
            // Gradient lengths come from the token so tuning happens in
            // one place.
            ZStack {
                // Top
                LinearGradient(
                    colors: [ink.opacity(topAlpha), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: elevation.pressTopFraction)
                )

                // Left
                LinearGradient(
                    colors: [ink.opacity(sideAlpha), .clear],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: elevation.pressSideFraction, y: 0.5)
                )

                // Right
                LinearGradient(
                    colors: [.clear, ink.opacity(sideAlpha)],
                    startPoint: UnitPoint(x: 1 - elevation.pressSideFraction, y: 0.5),
                    endPoint: .trailing
                )
            }
            .allowsHitTesting(false)
        }
    }
}
