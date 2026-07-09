import SwiftUI

/// The page's block stack — the ONE scroll owner for a note page
/// (hybrid_page_edd.md §3.1, §5.2).
///
/// Feature view — no TCA imports. Renders the page's blocks as
/// non-scrolling, self-sized rows inside a single vertical
/// `ScrollView`. Rows never scroll themselves: text editors report
/// their content height and are framed to it; ink blocks (Phase 2)
/// occupy their `heightPoints`.
///
/// **Phase 1 scope.** Exactly one row — the page's text block. The
/// row model arrives fully resolved from the wiring view (including
/// the min-height floor that keeps a short note filling the viewport
/// so taps below the last line still land in the editor). The
/// generalization to N heterogeneous rows is Phase 2/3; this view is
/// where those rows will mount.
///
/// **Slash popover.** The popover modifier is applied to THIS view by
/// the wiring — the stack container is the stationary anchor view the
/// stack-viewport-space caret rects are expressed in. Applying it to
/// a row would anchor to a moving view and the popover would drift on
/// scroll.
struct PageBlockStackView: View {
    let model: Model

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                TextBlockView(model: model.textBlock)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Model

extension PageBlockStackView {
    struct Model {
        let textBlock: TextBlockView.Model
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
    }
}

// MARK: - Model init (resolves design tokens)

extension PageBlockStackView.Model {
    init(
        textBlock: TextBlockView.Model,
        ds: DesignSystem = .standard
    ) {
        self.textBlock = textBlock
        self.horizontalPadding = ds.spacing.lg
        self.verticalPadding = ds.spacing.xl
    }
}
