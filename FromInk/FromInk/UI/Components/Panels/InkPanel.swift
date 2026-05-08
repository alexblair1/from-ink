import SwiftUI

// MARK: - Style

struct InkPanelStyle {
    let background: Color
    let height: CGFloat
    let horizontalPadding: CGFloat
    let dismissColor: Color

    static let standard = InkPanelStyle(
        background: ColorTokens.standard.surface,
        height: LayoutTokens.standard.hitTarget,
        horizontalPadding: SpacingScale.standard.base,
        dismissColor: ColorTokens.standard.ink2
    )
}

// MARK: - View

/// Generic panel container with title bar, optional tabs, content, and optional footer.
/// Used as the base for all side panels and sheets in the design system.
///
///     InkPanel(model: .init(title: "Headers", onDismiss: dismiss)) {
///         // scrollable content
///     }
///
///     InkPanel(model: .init(title: "Details", onDismiss: dismiss)) {
///         // content
///     } footer: {
///         InkButton("Save", style: .filled, action: save)
///     }
///
struct InkPanel<Content: View, Footer: View>: View {

    let model: Model
    let content: () -> Content
    let footer: () -> Footer

    init(
        model: Model,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.model = model
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                MonoLabel(model.title)
                Spacer()
                if let onDismiss = model.onDismiss {
                    IconButton("xmark", size: .footnote, color: model.style.dismissColor, action: onDismiss)
                }
            }
            .padding(.horizontal, model.style.horizontalPadding)
            .frame(height: model.style.height)

            HairlineRule()

            // Content
            content()

            // Footer
            footer()
        }
        .frame(width: model.width)
        .frame(maxHeight: .infinity)
        .background(model.style.background)
    }
}

// MARK: - Model

extension InkPanel {
    struct Model {
        let title: String
        let width: CGFloat
        let onDismiss: (() -> Void)?
        let style: InkPanelStyle

        init(
            title: String,
            width: CGFloat = LayoutTokens.standard.panelWidth,
            onDismiss: (() -> Void)? = nil,
            style: InkPanelStyle = .standard
        ) {
            self.title = title
            self.width = width
            self.onDismiss = onDismiss
            self.style = style
        }
    }
}
