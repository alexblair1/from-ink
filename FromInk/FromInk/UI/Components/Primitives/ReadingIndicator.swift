import SwiftUI

/// Generic "thinking…" affordance for the moments between user
/// initiating something (lasso → bolt, brief regeneration tap, etc.)
/// and the resulting content landing in view. A small `ProgressView`
/// stacked above a single line of italic serif text.
///
/// Reused by:
///   - `DispatchView` while OCR / extraction is in flight from the
///     lasso flow.
///   - `HomeDailyBrief` while Foundation Models is generating the
///     focus / suggestion text (callers in that view).
///
/// Visual treatment matches `BriefSheet.loadingState`'s original
/// shape (ProgressView + label) but uses serif italic and design
/// tokens so the experience is consistent across surfaces.
///
/// The caller is responsible for animating the indicator's
/// appearance / disappearance — wrap the conditional rendering in
/// `.animation(.linear(duration: ...), value: isLoading)` or use
/// `.transition(.opacity)` per CLAUDE.md's 80–120ms linear rule.
struct ReadingIndicator: View {
    let model: Model

    var body: some View {
        VStack(spacing: model.spacing) {
            ProgressView()
                .controlSize(model.controlSize)
                .tint(model.tint)
            Text(model.label)
                .font(model.labelFont)
                .italic()
                .foregroundStyle(model.labelColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

extension ReadingIndicator {
    struct Model {
        let label: String
        let labelFont: Font
        let labelColor: Color
        let tint: Color
        let spacing: CGFloat
        let controlSize: ControlSize
    }
}

extension ReadingIndicator.Model {
    /// Default style — italic serif body label, tinted to `ink2`,
    /// regular-size spinner. Used by `DispatchView` and `HomeDailyBrief`.
    init(
        label: String,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        // Serif body — matches the editorial tone the brief surfaces use
        // for AI-generated text. `.italic()` is applied at the view layer.
        self.labelFont = .system(.body, design: .serif)
        self.labelColor = ds.colors.ink2
        self.tint = ds.colors.ink2
        self.spacing = ds.spacing.sm
        self.controlSize = .regular
    }
}
