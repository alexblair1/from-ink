import SwiftUI

/// Compact dialog for naming/renaming items. Centered text field with cancel/confirm.
///
///     NameDialog(model: .init(
///         title: "New Notebook",
///         placeholder: "Untitled",
///         onCancel: dismiss,
///         onConfirm: { name in create(name) }
///     ))
///
struct NameDialog: View {

    let model: Model

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(model: Model) {
        self.model = model
        _text = State(initialValue: model.initialValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            MonoLabel(model.title)
                .padding(.top, model.style.padding)
                .padding(.bottom, model.style.padding)

            HairlineRule()

            // Text field
            TextField(model.placeholder, text: $text)
                .font(model.style.bodyFont)
                .foregroundStyle(model.style.bodyColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SpacingScale.standard.lg)
                .padding(.vertical, model.style.padding)
                .focused($isFocused)
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    model.onConfirm(text)
                }

            HairlineRule()

            // Actions
            HStack(spacing: 0) {
                Button(action: model.onCancel) {
                    Text(AppStrings.Common.cancel)
                        .font(model.style.cancelFont)
                        .foregroundStyle(model.style.cancelColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingScale.standard.md)
                }
                .buttonStyle(.plain)

                HairlineRule(.vertical)

                Button {
                    model.onConfirm(text)
                } label: {
                    Text(model.confirmLabel)
                        .font(model.style.confirmFont)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespaces).isEmpty
                                ? model.style.disabledColor
                                : model.style.enabledColor
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingScale.standard.md)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(height: model.style.actionHeight)
        }
        .frame(width: model.style.dialogWidth)
        .background(model.style.background)
        .onAppear { isFocused = true }
    }
}

extension NameDialog {
    struct Style {
        let bodyFont: Font
        let bodyColor: Color
        let cancelFont: Font
        let cancelColor: Color
        let confirmFont: Font
        let disabledColor: Color
        let enabledColor: Color
        let background: Color
        let padding: CGFloat
        let dialogWidth: CGFloat
        let actionHeight: CGFloat

        static let standard = Style(
            bodyFont: TypographyTokens.standard.body,
            bodyColor: ColorTokens.standard.ink,
            cancelFont: TypographyTokens.standard.subheadline,
            cancelColor: ColorTokens.standard.ink2,
            confirmFont: TypographyTokens.standard.subheadline,
            disabledColor: ColorTokens.standard.ink3,
            enabledColor: ColorTokens.standard.ink,
            background: ColorTokens.standard.surface,
            padding: SpacingScale.standard.base,
            dialogWidth: LayoutTokens.standard.dialogWidth,
            actionHeight: LayoutTokens.standard.dialogActionHeight
        )
    }

    struct Model {
        let title: String
        let placeholder: String
        let initialValue: String
        let confirmLabel: String
        let onCancel: () -> Void
        let onConfirm: (String) -> Void
        let style: Style

        init(
            title: String,
            placeholder: String = "Untitled",
            initialValue: String = "",
            confirmLabel: String = "Create",
            onCancel: @escaping () -> Void,
            onConfirm: @escaping (String) -> Void,
            style: Style = .standard
        ) {
            self.title = title
            self.placeholder = placeholder
            self.initialValue = initialValue
            self.confirmLabel = confirmLabel
            self.onCancel = onCancel
            self.onConfirm = onConfirm
            self.style = style
        }
    }
}
