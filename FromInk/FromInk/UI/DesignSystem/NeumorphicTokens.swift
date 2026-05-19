import SwiftUI

/// Design tokens for the "stamped paper" neumorphic surface treatment.
///
/// Two tokens live here:
///
/// - `NeumorphicElevation` — shadow and highlight values for the raised and
///   pressed states, in both light and dark themes. The CSS spec from
///   `Notebook Tabs - Dark Mode` is encoded as data; consumers
///   (`NeumorphicSurface`) read these values rather than hardcoding them.
///
/// - `NeumorphicTabStyle` — geometry of any neumorphic tab strip: tab
///   padding, content font sizes, the seam-killer paper strip dimensions,
///   and the panel overlap derived from those. Both `NeumorphicTabStrip`
///   and any panel container (`BriefTabSection`) consume the same style
///   so the seam math can't drift across files.
///

// MARK: - ShadowSpec

/// Single shadow descriptor (one row in a CSS `box-shadow` stack).
struct ShadowSpec: Sendable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - NeumorphicElevation

struct NeumorphicElevation: Sendable {
    // ── Light raise ────────────────────────────────────────────
    // Multiple outset shadows compose the "v3 Whisper" raise —
    // a white top highlight + four faint ink edges.
    let lightRaiseShadows: [ShadowSpec]

    // ── Dark raise ─────────────────────────────────────────────
    // Single inset top highlight only — outset shadows render as
    // visible hairlines on dark paper. The highlight alone reads.
    let darkRaiseHighlightColor: Color
    let darkRaiseHighlightHeight: CGFloat

    // ── Press (both themes) ────────────────────────────────────
    // Inset shadow synthesized via three gradient strips. Top edge
    // gets the strongest inset; sides at a multiplier of the top.
    // Bottom intentionally has no shadow so the surface bleeds
    // into whatever sits beneath (the panel pattern).
    let pressInkColor: Color
    let lightPressTopAlpha: Double
    let darkPressTopAlpha: Double
    let pressSideAlphaMultiplier: Double
    /// Vertical extent of the top gradient as a fraction of the
    /// view's height. Tighter = the shadow hugs the edge instead
    /// of bleeding into the content.
    let pressTopFraction: CGFloat
    /// Horizontal extent of each side gradient as a fraction of
    /// the view's width.
    let pressSideFraction: CGFloat

    static let standard = NeumorphicElevation(
        // Light raise — composite of five subtle shadows.
        lightRaiseShadows: [
            .init(color: .white.opacity(0.6),              radius: 1, x: 0, y: -1),
            .init(color: Color(white: 0.12).opacity(0.02), radius: 2, x: 0, y: -1),
            .init(color: Color(white: 0.12).opacity(0.03), radius: 2, x: 0, y: 1),
            .init(color: Color(white: 0.12).opacity(0.02), radius: 2, x: -1, y: 0),
            .init(color: Color(white: 0.12).opacity(0.02), radius: 2, x: 1, y: 0),
        ],

        // Dark raise — warm cream highlight along the top edge.
        darkRaiseHighlightColor: Color(white: 0.93).opacity(0.08),
        darkRaiseHighlightHeight: 1,

        // Press — pure black ink, alpha modulated per theme.
        pressInkColor: .black,
        lightPressTopAlpha: 0.04,
        darkPressTopAlpha: 0.28,
        pressSideAlphaMultiplier: 0.6,
        pressTopFraction: 0.07,
        pressSideFraction: 0.025
    )
}

// MARK: - NeumorphicTabStyle

struct NeumorphicTabStyle: Sendable {
    // ── Tab geometry ───────────────────────────────────────────
    let tabPaddingHorizontal: CGFloat
    let tabPaddingVertical: CGFloat

    // ── Content typography ─────────────────────────────────────
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let labelTracking: CGFloat
    let countFontSize: CGFloat
    let contentGap: CGFloat

    // ── Seam killer + panel overlap ───────────────────────────
    /// Height of the paper-colored strip rendered at the bottom
    /// of the active tab that overlaps the panel below.
    let seamHeight: CGFloat
    /// Inset of the seam strip from each side of the active tab,
    /// so the surrounding pressed shadows remain visible.
    let seamHorizontalInset: CGFloat
    /// Vertical distance the seam strip extends below the tab's
    /// bottom edge.
    let seamOffset: CGFloat

    /// Negative top inset the panel must apply to slide under
    /// the active tab's bottom edge. Mathematically equal to
    /// `-seamOffset` — consumers should always derive this rather
    /// than hardcode their own value, so any future tuning of
    /// `seamOffset` updates the panel automatically.
    var panelOverlap: CGFloat { -seamOffset }

    static let standard = NeumorphicTabStyle(
        tabPaddingHorizontal: 18,
        tabPaddingVertical: 14,
        iconSize: 14,
        labelFontSize: 10.5,
        labelTracking: 2.3,
        countFontSize: 18,
        contentGap: 10,
        seamHeight: 5,
        seamHorizontalInset: 4,
        seamOffset: 3
    )
}
