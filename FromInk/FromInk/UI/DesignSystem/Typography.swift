import SwiftUI

// MARK: - Typography Tokens
//
// System fonts only — no custom fonts shipped.
// SF Pro (sans), New York (serif), SF Mono (mono).
//
// Role          Apple style     Size   Weight      Used for
// Display       custom          48-96  Light       Date masthead, marquee
// LargeTitle    .largeTitle     34     Bold        Top-level screen titles
// Title         .title          28     Semibold    Section headers
// Headline      .headline       17     Semibold    List row primary text
// Body          .body           17     Regular     Default body, list rows
// EditorBody    custom          18     Regular     Note editor (serif body)
// Callout       .callout        16     Regular     Subtitles, contextual
// Subheadline   .subheadline    15     Regular     Secondary list metadata
// Footnote      .footnote       13     Regular     Captions, edited-at
// Caption       .caption        12     Regular     Tab Bar labels
// MonoLabel     custom          11     Medium      Eyebrows, runners, status

struct TypographyTokens: Sendable {

    // Display — New York Light, date mastheads, marquee titles.
    func display(size: CGFloat = 64) -> Font {
        .system(size: size, weight: .light, design: .serif)
    }

    var largeTitle: Font { .largeTitle.bold() }
    var title: Font { .title.weight(.semibold) }
    var title2: Font { .title2.weight(.semibold) }
    var headline: Font { .headline }
    var body: Font { .body }
    var callout: Font { .callout }
    var subheadline: Font { .subheadline }
    var footnote: Font { .footnote }
    var caption: Font { .caption }

    /// Editor body — New York Regular 18/26. Only place serif body lives.
    var editorBody: Font {
        .system(size: 18, weight: .regular, design: .serif)
    }

    /// Editor heading — New York Italic for note headings.
    var editorHeading: Font {
        .system(size: 24, weight: .semibold, design: .serif)
            .italic()
    }

    /// Mono label — SF Mono Medium 11pt. Pair with .monoLabelStyle().
    var monoLabel: Font {
        .system(size: 11, weight: .medium, design: .monospaced)
    }

    /// Mono small — SF Mono Regular 10pt. Dense metadata in panels.
    var monoSmall: Font {
        .system(size: 10, weight: .regular, design: .monospaced)
    }

    /// Large numerals — New York tabular figures for counts and dates.
    func numerals(size: CGFloat = 56) -> Font {
        .system(size: size, weight: .light, design: .serif)
    }

    static let standard = TypographyTokens()
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

    /// Nav bar title: New York Medium 17pt, -1% tracking.
    func navTitleStyle() -> some View {
        self
            .font(.system(size: 17, weight: .medium, design: .serif))
            .tracking(17 * -0.01)
    }
}
