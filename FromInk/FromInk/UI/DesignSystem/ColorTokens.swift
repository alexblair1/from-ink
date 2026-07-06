import SwiftUI

/// Adaptive named colors from the asset catalog.
/// All `Color` values resolve light/dark variants at render time.
///
/// Asset catalog: Assets.xcassets/ink/{Paper,Surface,Highlight,Ink,Ink2,Ink3,Rule,FlagRed}.colorset
///
/// Do NOT add default values to fields — compile-time enforcement that
/// every theme defines every token.
///
struct ColorTokens: Sendable {
    let paper: Color
    let surface: Color
    let highlight: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let rule: Color
    let paperOnInk: Color
    /// Pure black (light) / pure white (dark). Reserved for the
    /// inverted-pill selection state where the warm-tinted `ink`
    /// token reads as too muted against `paper`. Use sparingly —
    /// most surfaces should still use `ink`.
    let inkPure: Color
    /// Pure white (light) / pure black (dark). Pairs with `inkPure`
    /// as the icon color on an inverted-pill background.
    let paperPure: Color

    /// Editorial alert / needs-attention color. Reserved for explicit
    /// user-actionable callouts — "Re-authenticate", "No connection",
    /// "Permissions denied" — never decoration. Sourced from the
    /// design system: `--flag: #B5392A` on light, brightened on dark.
    /// Use sparingly; this is the loudest color in the palette.
    let flagRed: Color

    /// Ink-to-execution accent ("bolt"). The one sanctioned amber in an
    /// otherwise monochrome palette — marks the brief/dispatch trigger
    /// (`sparkles.rectangle.stack`). Use only for that affordance, never
    /// as decoration. Migrated from the legacy `Color.bolt`.
    let bolt: Color

    /// Ruled-line template guides drawn on the canvas (college rule, grid,
    /// dot). A muted lavender-grey that recedes behind ink. Migrated from
    /// the legacy `Color.ruleLine`.
    let ruleLine: Color

    // MARK: Text editor block chrome (readiness audit B5)
    //
    // Drawn by `BlockDecoratingLayoutManager` — these replace the
    // `UIColor.label.withAlphaComponent(...)` literals so the editor's
    // block chrome participates in theming like every other surface.
    // Alphas are baked into the color sets.

    /// Blockquote paragraph wash (label @ 4%).
    let blockquoteBackground: Color
    /// Blockquote leading bar (label @ 40%).
    let blockquoteBar: Color
    /// Code block + inline-code background (label @ 6%).
    let codeBackground: Color
    /// Divider block rule (label @ 25%).
    let dividerRule: Color
    /// Bullet / ordinal list markers (label @ 85%).
    let listMarker: Color

    // MARK: Text editor content colors (readiness audit B5)
    //
    // These are CONTENT emphasis, not UI chrome — the monochrome-chrome
    // rule doesn't apply to what the user authored.

    /// Link runs in rich text.
    let link: Color
    /// Highlight-mark backgrounds. Alphas baked into the color sets.
    let highlightYellow: Color
    let highlightRed: Color
    let highlightBlue: Color
    let highlightGreen: Color

    // Semantic aliases (computed, not stored)
    var tint: Color { ink }
    var selection: Color { highlight }
    var primaryLabel: Color { ink }
    var secondaryLabel: Color { ink2 }
    var tertiaryLabel: Color { ink3 }
    var separator: Color { rule }

    static let standard = ColorTokens(
        paper:      Color("ink/Paper"),
        surface:    Color("ink/Surface"),
        highlight:  Color("ink/Highlight"),
        ink:        Color("ink/Ink"),
        ink2:       Color("ink/Ink2"),
        ink3:       Color("ink/Ink3"),
        rule:       Color("ink/Rule"),
        paperOnInk: Color("ink/Paper"),
        inkPure:    Color("ink/InkPure"),
        paperPure:  Color("ink/PaperPure"),
        flagRed:    Color("ink/FlagRed"),
        bolt:       Color("ink/Bolt"),
        ruleLine:   Color("ink/RuleLine"),
        blockquoteBackground: Color("ink/BlockquoteBackground"),
        blockquoteBar:        Color("ink/BlockquoteBar"),
        codeBackground:       Color("ink/CodeBackground"),
        dividerRule:          Color("ink/DividerRule"),
        listMarker:           Color("ink/ListMarker"),
        link:                 Color("ink/Link"),
        highlightYellow:      Color("ink/HighlightYellow"),
        highlightRed:         Color("ink/HighlightRed"),
        highlightBlue:        Color("ink/HighlightBlue"),
        highlightGreen:       Color("ink/HighlightGreen")
    )
}
