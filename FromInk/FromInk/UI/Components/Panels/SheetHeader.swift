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
    let style: Style

    init(
        title: String,
        leadingAction: (String, () -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        style: Style = .standard
    ) {
        self.title = title
        if let leadingAction {
            self.leadingAction = (leadingAction.0, leadingAction.1)
        } else {
            self.leadingAction = nil
        }
        self.onDismiss = onDismiss
        self.style = style
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let leadingAction {
                    Button(action: leadingAction.handler) {
                        Text(leadingAction.label)
                            .font(style.labelFont)
                            .foregroundStyle(style.labelColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: style.headerSpacer)
                }

                Spacer()

                MonoLabel(title)

                Spacer()

                if let onDismiss {
                    IconButton("xmark", size: .footnote, color: style.dismissColor, action: onDismiss)
                        .frame(width: style.headerSpacer, alignment: .trailing)
                } else {
                    Spacer().frame(width: style.headerSpacer)
                }
            }
            .padding(.horizontal, style.horizontalPadding)
            .frame(height: style.height)

            HairlineRule()
        }
    }
}

extension SheetHeader {
    struct Style {
        let labelFont: Font
        let labelColor: Color
        let height: CGFloat
        let horizontalPadding: CGFloat
        let headerSpacer: CGFloat
        let dismissColor: Color

        static let standard = Style(
            labelFont: TypographyTokens.standard.subheadline,
            labelColor: ColorTokens.standard.ink,
            height: LayoutTokens.standard.sheetHeaderHeight,
            horizontalPadding: SpacingScale.standard.base,
            headerSpacer: LayoutTokens.standard.headerSpacer,
            dismissColor: ColorTokens.standard.ink2
        )
    }
}
