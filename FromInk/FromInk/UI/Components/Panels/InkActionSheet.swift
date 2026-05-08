import SwiftUI

/// Bottom action sheet with grouped action rows and cancel button.
///
///     InkActionSheet(model: .init(
///         title: "Note Options",
///         actions: [
///             .init(label: "Share", icon: "square.and.arrow.up", handler: share),
///             .init(label: "Duplicate", icon: "plus.square.on.square", handler: duplicate),
///             .init(label: "Delete", icon: "trash", isDestructive: true, handler: delete),
///         ],
///         onCancel: dismiss
///     ))
///
struct InkActionSheet: View {

    let model: Model

    var body: some View {
        VStack(spacing: model.style.groupSpacing) {
            // Actions group
            VStack(spacing: 0) {
                if let title = model.title {
                    MonoLabel(title, color: model.style.titleColor)
                        .padding(.vertical, model.style.itemPadding)
                    HairlineRule()
                }

                ForEach(Array(model.actions.enumerated()), id: \.offset) { index, action in
                    Button(action: action.handler) {
                        HStack(spacing: model.style.itemPadding) {
                            if let icon = action.icon {
                                Image(systemName: icon)
                                    .font(model.style.bodyFont)
                                    .symbolRenderingMode(.monochrome)
                                    .frame(width: model.style.iconFrame)
                            }
                            Text(action.label)
                                .font(model.style.bodyFont)
                            Spacer()
                        }
                        .foregroundStyle(
                            action.isDestructive ? model.style.destructiveColor : model.style.bodyColor
                        )
                        .padding(.horizontal, model.style.horizontalPadding)
                        .padding(.vertical, model.style.itemPadding)
                    }
                    .buttonStyle(.plain)

                    if index < model.actions.count - 1 {
                        HairlineRule()
                    }
                }
            }
            .background(model.style.background)

            // Cancel
            Button(action: model.onCancel) {
                Text(AppStrings.Common.cancel)
                    .font(model.style.cancelFont)
                    .fontWeight(.medium)
                    .foregroundStyle(model.style.cancelColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, model.style.itemPadding)
            }
            .buttonStyle(.plain)
            .background(model.style.background)
        }
        .padding(.horizontal, model.style.outerSpacing)
    }
}

extension InkActionSheet {
    struct Style {
        let bodyFont: Font
        let bodyColor: Color
        let cancelFont: Font
        let cancelColor: Color
        let titleColor: Color
        let destructiveColor: Color
        let background: Color
        let iconFrame: CGFloat
        let groupSpacing: CGFloat
        let itemPadding: CGFloat
        let horizontalPadding: CGFloat
        let outerSpacing: CGFloat

        static let standard = Style(
            bodyFont: TypographyTokens.standard.body,
            bodyColor: ColorTokens.standard.ink,
            cancelFont: TypographyTokens.standard.body,
            cancelColor: ColorTokens.standard.ink,
            titleColor: ColorTokens.standard.ink3,
            destructiveColor: .red,
            background: ColorTokens.standard.surface,
            iconFrame: LayoutTokens.standard.iconFrame,
            groupSpacing: SpacingScale.standard.sm,
            itemPadding: SpacingScale.standard.md,
            horizontalPadding: SpacingScale.standard.base,
            outerSpacing: SpacingScale.standard.sm
        )
    }

    struct Model {
        let title: String?
        let actions: [Action]
        let onCancel: () -> Void
        let style: Style

        init(
            title: String? = nil,
            actions: [Action],
            onCancel: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.title = title
            self.actions = actions
            self.onCancel = onCancel
            self.style = style
        }
    }

    struct Action {
        let label: String
        let icon: String?
        let isDestructive: Bool
        let handler: () -> Void

        init(
            label: String,
            icon: String? = nil,
            isDestructive: Bool = false,
            handler: @escaping () -> Void
        ) {
            self.label = label
            self.icon = icon
            self.isDestructive = isDestructive
            self.handler = handler
        }
    }
}
