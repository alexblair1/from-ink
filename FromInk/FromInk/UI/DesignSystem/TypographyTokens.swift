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

    // MARK: - Home screen styles

    /// "From Ink" wordmark — New York 18pt regular italic.
    let wordmark: Font
    /// Brief lede — first sentence summary — New York 19pt light.
    let briefLede: Font
    /// Notebook card titles — New York 13pt regular.
    let cardTitle: Font
    /// Text input title fields — New York 20pt regular.
    let inputTitle: Font
    /// Masthead weekday — New York 56pt regular.
    let mastheadWeekday: Font
    /// Masthead month/day — New York 40pt regular italic.
    let mastheadMonthDay: Font
    /// Button label — SF Pro 15pt medium.
    let buttonLabel: Font

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
        largeTitle:       .largeTitle.bold(),
        title:            .title.weight(.semibold),
        title2:           .title2.weight(.semibold),
        headline:         .headline,
        body:             .body,
        callout:          .callout,
        subheadline:      .subheadline,
        footnote:         .footnote,
        caption:          .caption,
        editorBody:       .system(size: 18, weight: .regular, design: .serif),
        editorHeading:    .system(size: 24, weight: .semibold, design: .serif).italic(),
        noteBody:         .system(size: 16, weight: .regular, design: .default),
        monoLabel:        .system(size: 11, weight: .medium, design: .monospaced),
        monoSmall:        .system(size: 10, weight: .regular, design: .monospaced),
        wordmark:         .system(size: 18, weight: .regular, design: .serif).italic(),
        briefLede:        .system(size: 19, weight: .light, design: .serif),
        cardTitle:        .system(size: 13, weight: .regular, design: .serif),
        inputTitle:       .system(size: 20, weight: .regular, design: .serif),
        mastheadWeekday:  .system(size: 56, weight: .regular, design: .serif),
        mastheadMonthDay: .system(size: 40, weight: .regular, design: .serif).italic(),
        buttonLabel:      .system(size: 15, weight: .medium, design: .default)
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
