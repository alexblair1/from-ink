import SwiftUI

/// Sheet footer with secondary (ghost) and primary (filled) action buttons.
///
///     SheetFooter(
///         secondary: .init("Cancel", action: dismiss),
///         primary: .init("Save", action: save)
///     )
///
///     SheetFooter(
///         secondary: .init("Edit Brief", action: edit),
///         primary: .init("Send All", action: send, isDisabled: isEmpty)
///     )
///
struct SheetFooter: View {
    let secondary: Action?
    let primary: Action

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: 12) {
                if let secondary {
                    InkButton(secondary.label, style: .ghost, action: secondary.handler)
                }

                Spacer()

                InkButton(primary.label, style: .filled, action: primary.handler)
                    .opacity(primary.isDisabled ? 0.4 : 1)
                    .allowsHitTesting(!primary.isDisabled)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
        }
        .background(Color("ink/Surface"))
    }
}

extension SheetFooter {
    struct Action {
        let label: String
        let isDisabled: Bool
        let handler: () -> Void

        init(_ label: String, action: @escaping () -> Void, isDisabled: Bool = false) {
            self.label = label
            self.isDisabled = isDisabled
            self.handler = action
        }
    }
}
