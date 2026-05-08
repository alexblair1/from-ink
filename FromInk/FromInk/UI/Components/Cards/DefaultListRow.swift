import SwiftUI

/// Standard two-line list row with leading icon, title, subtitle, and trailing accessory.
///
///     DefaultListRow(model: .init(
///         title: "Product Sync",
///         subtitle: "Last edited 2h ago",
///         icon: "doc.text",
///         onTap: { }
///     ))
///
struct DefaultListRow: View {
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

                    VStack(alignment: .leading, spacing: model.style.titleSpacing) {
                        Text(model.title)
                            .font(model.style.titleFont)
                            .foregroundStyle(model.style.titleColor)
                            .lineLimit(1)

                        if let subtitle = model.subtitle {
                            Text(subtitle)
                                .font(model.style.subtitleFont)
                                .foregroundStyle(model.style.subtitleColor)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let metadata = model.metadata {
                        MonoLabel(metadata, color: model.style.metadataColor)
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

extension DefaultListRow {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let subtitleFont: Font
        let subtitleColor: Color
        let iconFont: Font
        let iconColor: Color
        let metadataColor: Color
        let chevronColor: Color
        let chevronFont: Font
        let iconFrame: CGFloat
        let innerSpacing: CGFloat
        let titleSpacing: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.headline,
            titleColor: ColorTokens.standard.ink,
            subtitleFont: TypographyTokens.standard.subheadline,
            subtitleColor: ColorTokens.standard.ink2,
            iconFont: TypographyTokens.standard.body,
            iconColor: ColorTokens.standard.ink2,
            metadataColor: ColorTokens.standard.ink3,
            chevronColor: ColorTokens.standard.ink3,
            chevronFont: TypographyTokens.standard.footnote,
            iconFrame: LayoutTokens.standard.iconFrame,
            innerSpacing: SpacingScale.standard.md,
            titleSpacing: SpacingScale.standard.xxs,
            verticalPadding: SpacingScale.standard.md,
            horizontalPadding: SpacingScale.standard.base
        )
    }

    struct Model {
        let id: UUID
        let title: String
        let subtitle: String?
        let icon: String?
        let metadata: String?
        let showChevron: Bool
        let onTap: () -> Void
        let style: Style

        init(
            id: UUID = UUID(),
            title: String,
            subtitle: String? = nil,
            icon: String? = nil,
            metadata: String? = nil,
            showChevron: Bool = true,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.metadata = metadata
            self.showChevron = showChevron
            self.onTap = onTap
            self.style = style
        }
    }
}
