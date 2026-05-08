import SwiftUI

// MARK: - Spacing Scale (multiples of 4)
//
//   xxs   2pt   hairline nudge
//   xs    4pt   tight inner padding
//   sm    8pt   icon gap, compact padding
//   md   12pt   intra-group spacing
//   base 16pt   default list row horizontal padding
//   lg   24pt   section gap, card padding
//   xl   32pt   section margin
//   xxl  48pt   page-level insets

struct SpacingScale: Sendable {
    let xxs:  CGFloat = 2
    let xs:   CGFloat = 4
    let sm:   CGFloat = 8
    let md:   CGFloat = 12
    let base: CGFloat = 16
    let lg:   CGFloat = 24
    let xl:   CGFloat = 32
    let xxl:  CGFloat = 48

    static let standard = SpacingScale()
}

// MARK: - Corner Radius Scale
//
// Content surfaces use radius 0 (hairline rules are the structural element).
// Apple's continuous corner radii apply to chrome.
//
//   content  0    list rows, note cards, editor
//   chip     6    buttons, tag pills
//   row     10    list containers, popovers
//   sheet   14    modal sheets, alerts

struct CornerRadiusScale: Sendable {
    let content: CGFloat = 0
    let chip:    CGFloat = 6
    let row:     CGFloat = 10
    let sheet:   CGFloat = 14

    static let standard = CornerRadiusScale()
}

// MARK: - Animation Tokens
//
// Linear only — no spring physics, no bounce.

struct AnimationTokens: Sendable {
    /// 80ms — tool selection, icon state changes.
    var fast: Animation { .linear(duration: 0.08) }

    /// 100ms — toolbar visibility, panel slides.
    var standard: Animation { .linear(duration: 0.10) }

    /// 120ms — page-level transitions.
    var slow: Animation { .linear(duration: 0.12) }

    static let standard = AnimationTokens()
}

// MARK: - Material Role
//
//   navBar/tabBar    .regularMaterial   reads as paper, content slides under
//   searchActive     .thinMaterial      lets list peek during query
//   toolbar          .thickMaterial     reads as a tool resting on the page
//
// Elevation:
//   0 onPaper    flat + hairline rule              list rows, cards, editor
//   1 floating   material + ink/8% hairline         toolbars, tag pills
//   2 sheet      system shadow (don't override)     modal sheets, popovers
//   3 alert      system shadow + blur (Apple owns)  alerts, action sheets

enum MaterialRole: Sendable {
    case navBar
    case tabBar
    case searchActive
    case toolbar
    case sheet

    var material: Material {
        switch self {
        case .navBar, .tabBar, .sheet: .regular
        case .searchActive:            .thin
        case .toolbar:                 .thick
        }
    }
}

enum ElevationLevel: Int, Sendable {
    case onPaper  = 0
    case floating = 1
    case sheet    = 2
    case alert    = 3
}
