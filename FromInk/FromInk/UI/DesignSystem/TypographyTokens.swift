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
    /// Masthead weekday for compact width class (iPhone, split-view).
    /// Smaller than the regular variant to accommodate verbose localized
    /// weekday names — "Mittwoch", "الأربعاء", "水曜日" — without wrapping.
    let mastheadWeekdayCompact: Font
    /// Masthead month/day for compact width class.
    let mastheadMonthDayCompact: Font
    /// Button label — SF Pro 15pt medium.
    let buttonLabel: Font

    // MARK: - Onboarding chrome
    //
    // Chrome presets only (kicker, button, secondary link, footer note,
    // body). Hero serif typography is resolved per-screen because each
    // onboarding screen has its own headline size in the design.

    /// "Kicker" — small mono uppercase eyebrow above each screen's
    /// headline. SF Mono, fixed 11pt so tracking and case treatment
    /// stay tight; callers apply `.tracking(0.24em)` + uppercase.
    let onboardingKicker: Font
    /// Body paragraph copy on each onboarding screen.
    /// SF Pro body style — scales with Dynamic Type.
    let onboardingBody: Font
    /// Primary CTA label on the footer button.
    /// SF Pro 16pt medium.
    let onboardingButtonLabel: Font
    /// Secondary "Not now" / "Maybe later" text link in the footer.
    /// SF Mono 11pt — paired with uppercase + 0.18em tracking.
    let onboardingTextLink: Font
    /// Mono uppercase note under the secondary link
    /// ("Then $11.99/year · Cancel anytime"). SF Mono 9.5pt.
    let onboardingFooterNote: Font

    // MARK: - Tracking
    //
    // Letter-spacing values paired with mono uppercase styles. SwiftUI's
    // `.tracking(_:)` modifier takes a CGFloat in points. Three named
    // values cover every mono-uppercase use site in the app.

    /// Tight tracking — for very small mono text (footer notes).
    let monoNoteTracking: CGFloat
    /// Standard mono uppercase tracking — for secondary text links,
    /// micro-card eyebrows, and short captions.
    let monoLinkTracking: CGFloat
    /// Wide tracking — for prominent eyebrows / kickers where the
    /// letterspacing should read as editorial.
    let kickerTracking: CGFloat

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
        mastheadWeekdayCompact:  .system(size: 32, weight: .regular, design: .serif),
        mastheadMonthDayCompact: .system(size: 22, weight: .regular, design: .serif).italic(),
        buttonLabel:      .system(size: 15, weight: .medium, design: .default),
        onboardingKicker:      .system(.caption2, design: .monospaced).weight(.medium),
        onboardingBody:        .system(.body, design: .default),
        onboardingButtonLabel: .system(.callout, design: .default).weight(.medium),
        onboardingTextLink:    .system(.caption2, design: .monospaced),
        onboardingFooterNote:  .system(.caption2, design: .monospaced),
        monoNoteTracking: 1.4,
        monoLinkTracking: 2.0,
        kickerTracking:   2.4
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
