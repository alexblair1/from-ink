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
        VStack(spacing: 16) {
            Spacer()

            if let icon = model.icon {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color("ink/Ink3"))
            }

            Text(model.message)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color("ink/Ink3"))
                .multilineTextAlignment(.center)

            if let actionLabel = model.actionLabel, let onAction = model.onAction {
                InkButton(actionLabel, style: .tinted, action: onAction)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

extension EmptyState {
    struct Model {
        let icon: String?
        let message: String
        let actionLabel: String?
        let onAction: (() -> Void)?

        init(
            icon: String? = nil,
            message: String,
            actionLabel: String? = nil,
            onAction: (() -> Void)? = nil
        ) {
            self.icon = icon
            self.message = message
            self.actionLabel = actionLabel
            self.onAction = onAction
        }
    }
}
