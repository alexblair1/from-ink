import SwiftUI

/// Minimal single-line row with leading icon and trailing accessory.
///
///     CompactListRow(model: .init(
///         title: "Settings",
///         icon: "gearshape",
///         onTap: { }
///     ))
///
struct CompactListRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(spacing: 0) {
                HStack(spacing: model.style.innerSpacing) {
                    if let icon = model.icon {
                        Image(systemName: icon)
                            .font(model.style.iconFont)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(model.style.iconColor)
                            .frame(width: model.style.iconFrame)
                    }

                    Text(model.title)
                        .font(model.style.titleFont)
                        .foregroundStyle(model.style.titleColor)
                        .lineLimit(1)

                    Spacer()

                    if let trailingText = model.trailingText {
                        Text(trailingText)
                            .font(model.style.trailingFont)
                            .foregroundStyle(model.style.trailingColor)
                    }

                    if model.showChevron {
                        Image(systemName: "chevron.right")
                            .font(model.style.chevronFont)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(model.style.chevronColor)
                    }
                }
                .padding(.vertical, model.style.verticalPadding)
                .padding(.horizontal, model.style.horizontalPadding)

                HairlineRule()
            }
        }
        .buttonStyle(.plain)
    }
}

extension CompactListRow {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let iconFont: Font
        let iconColor: Color
        let trailingFont: Font
        let trailingColor: Color
        let chevronFont: Font
        let chevronColor: Color
        let iconFrame: CGFloat
        let innerSpacing: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.body,
            titleColor: ColorTokens.standard.ink,
            iconFont: TypographyTokens.standard.body,
            iconColor: ColorTokens.standard.ink2,
            trailingFont: TypographyTokens.standard.subheadline,
            trailingColor: ColorTokens.standard.ink3,
            chevronFont: TypographyTokens.standard.footnote,
            chevronColor: ColorTokens.standard.ink3,
            iconFrame: LayoutTokens.standard.iconFrame,
            innerSpacing: SpacingScale.standard.md,
            verticalPadding: SpacingScale.standard.md,
            horizontalPadding: SpacingScale.standard.base
        )
    }

    struct Model {
        let title: String
        let icon: String?
        let trailingText: String?
        let showChevron: Bool
        let onTap: () -> Void
        let style: Style

        init(
            title: String,
            icon: String? = nil,
            trailingText: String? = nil,
            showChevron: Bool = true,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.title = title
            self.icon = icon
            self.trailingText = trailingText
            self.showChevron = showChevron
            self.onTap = onTap
            self.style = style
        }
    }
}
