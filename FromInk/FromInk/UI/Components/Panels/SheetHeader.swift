import SwiftUI

/// Modal sheet header with title and close button.
///
///     SheetHeader(title: "Share", onDismiss: dismiss)
///     SheetHeader(title: "New Notebook", leadingAction: ("Cancel", cancel))
///
struct SheetHeader: View {
    let title: String
    let leadingAction: (label: String, handler: () -> Void)?
    let onDismiss: (() -> Void)?

    init(
        title: String,
        leadingAction: (String, () -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        if let leadingAction {
            self.leadingAction = (leadingAction.0, leadingAction.1)
        } else {
            self.leadingAction = nil
        }
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let leadingAction {
                    Button(action: leadingAction.handler) {
                        Text(leadingAction.label)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color("ink/Ink"))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 60)
                }

                Spacer()

                MonoLabel(title, color: Color("ink/Ink2"))

                Spacer()

                if let onDismiss {
                    IconButton("xmark", size: .footnote, color: Color("ink/Ink2"), action: onDismiss)
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Spacer().frame(width: 60)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            HairlineRule()
        }
    }
}
