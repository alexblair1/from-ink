import SwiftUI

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
                MonoLabel(model.title, color: Color("ink/Ink2"))
                Spacer()
                if let onDismiss = model.onDismiss {
                    IconButton("xmark", size: .footnote, color: Color("ink/Ink2"), action: onDismiss)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            HairlineRule()

            // Content
            content()

            // Footer
            footer()
        }
        .frame(width: model.width)
        .frame(maxHeight: .infinity)
        .background(Color("ink/Surface"))
    }
}

extension InkPanel {
    struct Model {
        let title: String
        let width: CGFloat
        let onDismiss: (() -> Void)?

        init(
            title: String,
            width: CGFloat = 420,
            onDismiss: (() -> Void)? = nil
        ) {
            self.title = title
            self.width = width
            self.onDismiss = onDismiss
        }
    }
}
