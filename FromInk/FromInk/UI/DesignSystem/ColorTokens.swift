import SwiftUI

/// Adaptive named colors from the asset catalog.
/// All `Color` values resolve light/dark variants at render time.
///
/// Asset catalog: Assets.xcassets/ink/{Paper,Surface,Highlight,Ink,Ink2,Ink3,Rule}.colorset
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
        paperOnInk: Color("ink/Paper")
    )
}
