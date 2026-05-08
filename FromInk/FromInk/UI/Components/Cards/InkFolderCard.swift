import SwiftUI

/// Folder card showing name, notebook count, and optional icon.
///
///     InkFolderCard(model: .init(
///         name: "Work",
///         subtitle: "5 notebooks",
///         onTap: { }
///     ))
///
struct InkFolderCard: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: model.style.innerSpacing) {
                    Image(systemName: model.icon)
                        .font(model.style.iconFont)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.style.iconColor)

                    VStack(alignment: .leading, spacing: model.style.titleSpacing) {
                        Text(model.name)
                            .font(model.style.nameFont)
                            .foregroundStyle(model.style.nameColor)
                            .lineLimit(1)

                        MonoLabel(model.subtitle, color: model.style.subtitleColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(model.style.chevronFont)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.style.chevronColor)
                }
                .padding(model.style.padding)

                HairlineRule()
            }
            .background(model.style.background)
        }
        .buttonStyle(.plain)
    }
}

extension InkFolderCard {
    struct Style {
        let nameFont: Font
        let nameColor: Color
        let iconFont: Font
        let iconColor: Color
        let subtitleColor: Color
        let chevronFont: Font
        let chevronColor: Color
        let background: Color
        let innerSpacing: CGFloat
        let titleSpacing: CGFloat
        let padding: CGFloat

        static let standard = Style(
            nameFont: TypographyTokens.standard.headline,
            nameColor: ColorTokens.standard.ink,
            iconFont: TypographyTokens.standard.body,
            iconColor: ColorTokens.standard.ink2,
            subtitleColor: ColorTokens.standard.ink3,
            chevronFont: TypographyTokens.standard.footnote,
            chevronColor: ColorTokens.standard.ink3,
            background: ColorTokens.standard.surface,
            innerSpacing: SpacingScale.standard.md,
            titleSpacing: SpacingScale.standard.xs,
            padding: SpacingScale.standard.base
        )
    }

    struct Model {
        let id: UUID
        let name: String
        let subtitle: String
        let icon: String
        let onTap: () -> Void
        let style: Style

        init(
            id: UUID = UUID(),
            name: String,
            subtitle: String = "",
            icon: String = "folder",
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.id = id
            self.name = name
            self.subtitle = subtitle
            self.icon = icon
            self.onTap = onTap
            self.style = style
        }
    }
}
