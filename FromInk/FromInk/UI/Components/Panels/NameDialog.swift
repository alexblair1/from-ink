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
            MonoLabel(model.title, color: Color("ink/Ink2"))
                .padding(.top, 20)
                .padding(.bottom, 16)

            HairlineRule()

            // Text field
            TextField(model.placeholder, text: $text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color("ink/Ink"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .focused($isFocused)
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    model.onConfirm(text)
                }

            HairlineRule()

            // Actions
            HStack(spacing: 0) {
                Button(action: model.onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color("ink/Ink2"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                HairlineRule(.vertical)

                Button {
                    model.onConfirm(text)
                } label: {
                    Text(model.confirmLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color("ink/Ink3")
                                : Color("ink/Ink")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(height: 48)
        }
        .frame(width: 300)
        .background(Color("ink/Surface"))
        .onAppear { isFocused = true }
    }
}

extension NameDialog {
    struct Model {
        let title: String
        let placeholder: String
        let initialValue: String
        let confirmLabel: String
        let onCancel: () -> Void
        let onConfirm: (String) -> Void

        init(
            title: String,
            placeholder: String = "Untitled",
            initialValue: String = "",
            confirmLabel: String = "Create",
            onCancel: @escaping () -> Void,
            onConfirm: @escaping (String) -> Void
        ) {
            self.title = title
            self.placeholder = placeholder
            self.initialValue = initialValue
            self.confirmLabel = confirmLabel
            self.onCancel = onCancel
            self.onConfirm = onConfirm
        }
    }
}
