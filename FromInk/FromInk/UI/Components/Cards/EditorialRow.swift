import SwiftUI

/// Rich editorial row with title, excerpt, timestamp, and optional thumbnail.
/// Used for notebook entries, search results, and content previews.
///
///     EditorialRow(model: .init(
///         title: "Weekly Retro",
///         excerpt: "Discussed sprint velocity and upcoming milestones...",
///         timestamp: "May 05",
///         onTap: { }
///     ))
///
struct EditorialRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: model.style.innerSpacing) {
                    VStack(alignment: .leading, spacing: model.style.titleSpacing) {
                        Text(model.title)
                            .font(model.style.titleFont)
                            .foregroundStyle(model.style.titleColor)
                            .lineLimit(2)

                        if let excerpt = model.excerpt {
                            Text(excerpt)
                                .font(model.style.excerptFont)
                                .foregroundStyle(model.style.excerptColor)
                                .lineLimit(3)
                        }

                        HStack(spacing: model.style.metadataSpacing) {
                            if let timestamp = model.timestamp {
                                MonoLabel(timestamp, color: model.style.metadataColor)
                            }
                            if let tag = model.tag {
                                MonoLabel("· \(tag)", color: model.style.metadataColor)
                            }
                        }
                        .padding(.top, model.style.titleSpacing)
                    }

                    Spacer(minLength: 0)

                    if let thumbnail = model.thumbnail {
                        thumbnail
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: model.style.thumbnailSize,
                                height: model.style.thumbnailSize
                            )
                            .clipped()
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

extension EditorialRow {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let excerptFont: Font
        let excerptColor: Color
        let metadataColor: Color
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
        let innerSpacing: CGFloat
        let titleSpacing: CGFloat
        let metadataSpacing: CGFloat
        let thumbnailSize: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.headline,
            titleColor: ColorTokens.standard.ink,
            excerptFont: TypographyTokens.standard.subheadline,
            excerptColor: ColorTokens.standard.ink2,
            metadataColor: ColorTokens.standard.ink3,
            verticalPadding: SpacingScale.standard.md,
            horizontalPadding: SpacingScale.standard.base,
            innerSpacing: SpacingScale.standard.md,
            titleSpacing: SpacingScale.standard.xs,
            metadataSpacing: SpacingScale.standard.sm,
            thumbnailSize: LayoutTokens.standard.thumbnailSize
        )
    }

    struct Model {
        let id: UUID
        let title: String
        let excerpt: String?
        let timestamp: String?
        let tag: String?
        let thumbnail: Image?
        let onTap: () -> Void
        let style: Style

        init(
            id: UUID = UUID(),
            title: String,
            excerpt: String? = nil,
            timestamp: String? = nil,
            tag: String? = nil,
            thumbnail: Image? = nil,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.id = id
            self.title = title
            self.excerpt = excerpt
            self.timestamp = timestamp
            self.tag = tag
            self.thumbnail = thumbnail
            self.onTap = onTap
            self.style = style
        }
    }
}
