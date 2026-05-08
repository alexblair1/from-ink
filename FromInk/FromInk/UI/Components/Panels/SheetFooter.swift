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
    let style: Style

    init(
        secondary: Action? = nil,
        primary: Action,
        style: Style = .standard
    ) {
        self.secondary = secondary
        self.primary = primary
        self.style = style
    }

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: style.innerSpacing) {
                if let secondary {
                    InkButton(secondary.label, style: .ghost, action: secondary.handler)
                }

                Spacer()

                InkButton(primary.label, style: .filled, action: primary.handler)
                    .opacity(primary.isDisabled ? 0.4 : 1)
                    .allowsHitTesting(!primary.isDisabled)
            }
            .padding(.horizontal, style.horizontalPadding)
            .frame(height: style.height)
        }
        .background(style.background)
    }
}

extension SheetFooter {
    struct Style {
        let horizontalPadding: CGFloat
        let height: CGFloat
        let background: Color
        let innerSpacing: CGFloat

        static let standard = Style(
            horizontalPadding: SpacingScale.standard.base,
            height: LayoutTokens.standard.footerHeight,
            background: ColorTokens.standard.surface,
            innerSpacing: SpacingScale.standard.md
        )
    }

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
