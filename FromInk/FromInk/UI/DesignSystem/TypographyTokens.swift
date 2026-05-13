import SwiftUI

/// Named font presets using system-supplied typefaces only.
/// SF Pro (sans), New York (serif via .design(.serif)), SF Mono (monospaced).
/// No custom font files shipped — no bundling, licensing, or fallback handling.
///
/// All fonts use system APIs that respect Dynamic Type automatically.
///
struct TypographyTokens: Sendable {

    // MARK: - System text styles

    let largeTitle: Font
    let title: Font
    let title2: Font
    let headline: Font
    let body: Font
    let callout: Font
    let subheadline: Font
    let footnote: Font
    let caption: Font

    // MARK: - Custom styles

    let editorBody: Font
    let editorHeading: Font
    let noteBody: Font
    let monoLabel: Font
    let monoSmall: Font

    // MARK: - Parametric styles

    /// Display — New York Light, for date mastheads and marquee titles.
    func display(size: CGFloat = 64) -> Font {
        .system(size: size, weight: .light, design: .serif)
    }

    /// Large numerals — New York tabular figures for counts and dates.
    func numerals(size: CGFloat = 56) -> Font {
        .system(size: size, weight: .light, design: .serif)
    }

    // MARK: - Standard preset

    static let standard = TypographyTokens(
        largeTitle:    .largeTitle.bold(),
        title:         .title.weight(.semibold),
        title2:        .title2.weight(.semibold),
        headline:      .headline,
        body:          .body,
        callout:       .callout,
        subheadline:   .subheadline,
        footnote:      .footnote,
        caption:       .caption,
        editorBody:    .system(size: 18, weight: .regular, design: .serif),
        editorHeading: .system(size: 24, weight: .semibold, design: .serif).italic(),
        noteBody:      .system(size: 16, weight: .regular, design: .default),
        monoLabel:     .system(size: 11, weight: .medium, design: .monospaced),
        monoSmall:     .system(size: 10, weight: .regular, design: .monospaced)
    )
}

// MARK: - Text style modifiers

extension View {
    /// SF Mono Medium 11pt, +18% tracking, uppercase.
    func monoLabelStyle() -> some View {
        self
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(2.0)
            .textCase(.uppercase)
    }

    /// Display serif with -2% tracking.
    func displayStyle(size: CGFloat = 64) -> some View {
        self
            .font(.system(size: size, weight: .light, design: .serif))
            .tracking(size * -0.02)
    }

    /// New York Regular 18pt, 1.45 line spacing.
    func editorBodyStyle() -> some View {
        self
            .font(.system(size: 18, weight: .regular, design: .serif))
            .lineSpacing(8)
    }
}
