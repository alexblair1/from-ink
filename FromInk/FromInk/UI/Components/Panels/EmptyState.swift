import SwiftUI

/// Centered empty state with optional icon, message, and action.
///
///     EmptyState(model: .init(message: "No notebooks yet"))
///     EmptyState(model: .init(
///         icon: "book.closed",
///         message: "No notebooks yet",
///         actionLabel: "Create Notebook",
///         onAction: createNotebook
///     ))
///
struct EmptyState: View {

    let model: Model

    var body: some View {
        VStack(spacing: model.style.spacing) {
            Spacer()

            if let icon = model.icon {
                Image(systemName: icon)
                    .font(.system(size: model.style.iconSize, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.style.iconColor)
            }

            Text(model.message)
                .font(model.style.messageFont)
                .foregroundStyle(model.style.messageColor)
                .multilineTextAlignment(.center)

            if let actionLabel = model.actionLabel, let onAction = model.onAction {
                InkButton(actionLabel, style: .tinted, action: onAction)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, model.style.horizontalPadding)
    }
}

extension EmptyState {
    struct Style {
        let messageFont: Font
        let messageColor: Color
        let iconColor: Color
        let iconSize: CGFloat
        let spacing: CGFloat
        let horizontalPadding: CGFloat

        static let standard = Style(
            messageFont: TypographyTokens.standard.subheadline,
            messageColor: ColorTokens.standard.ink3,
            iconColor: ColorTokens.standard.ink3,
            iconSize: 32,
            spacing: SpacingScale.standard.base,
            horizontalPadding: SpacingScale.standard.xl
        )
    }

    struct Model {
        let icon: String?
        let message: String
        let actionLabel: String?
        let onAction: (() -> Void)?
        let style: Style

        init(
            icon: String? = nil,
            message: String,
            actionLabel: String? = nil,
            onAction: (() -> Void)? = nil,
            style: Style = .standard
        ) {
            self.icon = icon
            self.message = message
            self.actionLabel = actionLabel
            self.onAction = onAction
            self.style = style
        }
    }
}
