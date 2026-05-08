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
        VStack(spacing: 8) {
            // Actions group
            VStack(spacing: 0) {
                if let title = model.title {
                    MonoLabel(title, color: Color("ink/Ink3"))
                        .padding(.vertical, 12)
                    HairlineRule()
                }

                ForEach(Array(model.actions.enumerated()), id: \.offset) { index, action in
                    Button(action: action.handler) {
                        HStack(spacing: 12) {
                            if let icon = action.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 17, weight: .regular))
                                    .symbolRenderingMode(.monochrome)
                                    .frame(width: 24)
                            }
                            Text(action.label)
                                .font(.system(size: 17, weight: .regular))
                            Spacer()
                        }
                        .foregroundStyle(
                            action.isDestructive ? .red : Color("ink/Ink")
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if index < model.actions.count - 1 {
                        HairlineRule()
                    }
                }
            }
            .background(Color("ink/Surface"))

            // Cancel
            Button(action: model.onCancel) {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color("ink/Ink"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(Color("ink/Surface"))
        }
        .padding(.horizontal, 8)
    }
}

extension InkActionSheet {
    struct Model {
        let title: String?
        let actions: [Action]
        let onCancel: () -> Void

        init(
            title: String? = nil,
            actions: [Action],
            onCancel: @escaping () -> Void
        ) {
            self.title = title
            self.actions = actions
            self.onCancel = onCancel
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
