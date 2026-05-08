import SwiftUI

// MARK: - Design System
//
// Injectable design system for From Ink — Native Kit.
// All visual tokens flow from this one struct; inject via .designSystem(_:)
// and consume via @Environment(\.ds).
//
// Principles (from Native Kit, Edition 01):
//   - Native first, brand second
//   - System fonts only — SF Pro, New York, SF Mono
//   - Off-black ink (#1F1D1A) and paper-cream (#FAFAF8)
//   - No drop shadows on content; no custom corner radii on content surfaces
//   - SF Symbols only, monochrome rendering
//   - App tint = ink (not systemBlue)
//   - Linear 80-120ms animation; no spring physics
//
// Usage:
//   struct MyFeatureView: View {
//       @Environment(\.ds) private var ds
//       var body: some View {
//           Text("Hello")
//               .font(ds.typography.headline)
//               .foregroundStyle(ds.colors.ink)
//               .padding(ds.spacing.base)
//       }
//   }

struct DesignSystem: Sendable {
    var colors: ColorTokens
    var typography: TypographyTokens
    var spacing: SpacingScale
    var cornerRadius: CornerRadiusScale
    var animation: AnimationTokens

    init(
        colors: ColorTokens = .standard,
        typography: TypographyTokens = .standard,
        spacing: SpacingScale = .standard,
        cornerRadius: CornerRadiusScale = .standard,
        animation: AnimationTokens = .standard
    ) {
        self.colors = colors
        self.typography = typography
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.animation = animation
    }

    static let standard = DesignSystem()
}

// MARK: - Color Tokens
//
// Colors are named Asset Catalog entries — never raw hex in view code.
// Asset catalog: Assets.xcassets/ink/{Paper,Surface,Highlight,Ink,Ink2,Ink3,Rule}.colorset
//
// Token        Light      Dark       Use
// paper        #FAFAF8    #17171A    primary surface
// surface      #F0EFE9    #242428    grouped lists, cards
// highlight    #E8E4D0    #2A2A2E    selection, hover
// ink          #1F1D1A    #EDEAE0    primary label, app tint
// ink2         #5C5852    #9D9A91    secondary label
// ink3         #ACA8A1    #5E5B55    tertiary label, placeholder
// rule         ink@18%    ink@18%    hairline separator

struct ColorTokens: Sendable {
    var paper: Color
    var surface: Color
    var highlight: Color
    var ink: Color
    var ink2: Color
    var ink3: Color
    var rule: Color

    var tint: Color { ink }
    var selection: Color { highlight }
    var primaryLabel: Color { ink }
    var secondaryLabel: Color { ink2 }
    var tertiaryLabel: Color { ink3 }
    var separator: Color { rule }

    static let standard = ColorTokens(
        paper:     Color("ink/Paper"),
        surface:   Color("ink/Surface"),
        highlight: Color("ink/Highlight"),
        ink:       Color("ink/Ink"),
        ink2:      Color("ink/Ink2"),
        ink3:      Color("ink/Ink3"),
        rule:      Color("ink/Rule")
    )
}

// MARK: - Environment

private struct DesignSystemKey: EnvironmentKey {
    static let defaultValue = DesignSystem.standard
}

extension EnvironmentValues {
    var ds: DesignSystem {
        get { self[DesignSystemKey.self] }
        set { self[DesignSystemKey.self] = newValue }
    }
}

extension View {
    func designSystem(_ ds: DesignSystem) -> some View {
        environment(\.ds, ds)
    }
}
