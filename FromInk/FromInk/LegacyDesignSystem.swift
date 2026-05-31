import SwiftUI

// MARK: - LEGACY — DEPRECATED
//
// This file contains hardcoded Color and Font extensions used by the canvas
// and other legacy code. These should be migrated to use ColorTokens.standard
// and TypographyTokens.standard from the new design system.
//
// Once all consumers are migrated, delete this file.

// MARK: - Adaptive Color Helper

extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

// MARK: - Design Tokens

extension Color {
    /// Notebook writing surface. Matches the home screen via the
    /// shared `ink/Paper` asset so the open-notebook background is
    /// continuous with where the user opened it from.
    static let canvas = Color("ink/Paper")
    /// UI surface — toolbar, top bar
    static let surface = Color(
        light: Color(red: 0.99, green: 0.99, blue: 0.98),
        dark:  Color(red: 0.12, green: 0.12, blue: 0.12)
    )
    /// Subtle dividers and borders
    static let border = Color(
        light: Color(red: 0.88, green: 0.87, blue: 0.85),
        dark:  Color(red: 0.22, green: 0.22, blue: 0.22)
    )
    /// Primary ink — text, active icons
    static let ink = Color(
        light: Color(red: 0.08, green: 0.08, blue: 0.08),
        dark:  Color(red: 0.94, green: 0.94, blue: 0.94)
    )
    /// Secondary ink — inactive icons, captions
    static let inkSecondary = Color(
        light: Color(red: 0.52, green: 0.50, blue: 0.48),
        dark:  Color(red: 0.55, green: 0.55, blue: 0.55)
    )
    /// Icon color when sitting on an ink-filled background
    static let inkOnDark = Color(
        light: .white,
        dark:  Color(red: 0.09, green: 0.09, blue: 0.09)
    )
    /// Ink-to-execution bolt — amber accent
    static let bolt = Color(red: 1.0, green: 0.72, blue: 0.08)
    /// Ruled-line template guides
    static let ruleLine = Color(
        light: Color(red: 0.84, green: 0.83, blue: 0.88),
        dark:  Color(red: 0.20, green: 0.20, blue: 0.24)
    )
}

// MARK: - Typography

extension Font {
    /// Notebook title — New York serif, 17pt
    static let canvasTitle = Font.custom("NewYorkMedium-Regular", size: 17)
    /// Navigation label — SF Pro 14pt
    static let navLabel = Font.system(size: 14, weight: .regular)
}
