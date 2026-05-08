import SwiftUI

/// Vertical notebook spine for grid layouts. Shows cover color, title, and page count.
///
///     NotebookSpine(model: .init(
///         title: "Meeting Notes",
///         pageCount: 24,
///         coverColor: Color("ink/Ink"),
///         onTap: { }
///     ))
///
struct NotebookSpine: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Spine accent strip
                Rectangle()
                    .fill(model.coverColor)
                    .frame(height: model.style.stripHeight)

                VStack(alignment: .leading, spacing: model.style.innerSpacing) {
                    Text(model.title)
                        .font(model.style.titleFont)
                        .foregroundStyle(model.style.titleColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    MonoLabel(model.pageCountLabel, color: model.style.metadataColor)
                }
                .padding(model.style.padding)

                HairlineRule()
            }
            .frame(minHeight: model.style.minHeight)
            .background(model.style.background)
        }
        .buttonStyle(.plain)
    }
}

extension NotebookSpine {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let metadataColor: Color
        let background: Color
        let stripHeight: CGFloat
        let innerSpacing: CGFloat
        let padding: CGFloat
        let minHeight: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.subheadline,
            titleColor: ColorTokens.standard.ink,
            metadataColor: ColorTokens.standard.ink3,
            background: ColorTokens.standard.surface,
            stripHeight: 4,
            innerSpacing: SpacingScale.standard.sm,
            padding: SpacingScale.standard.md,
            minHeight: LayoutTokens.standard.spineMinHeight
        )
    }

    struct Model {
        let id: UUID
        let title: String
        let pageCount: Int
        let pageCountLabel: String
        let coverColor: Color
        let onTap: () -> Void
        let style: Style

        init(
            id: UUID = UUID(),
            title: String,
            pageCount: Int = 0,
            pageCountLabel: String? = nil,
            coverColor: Color = ColorTokens.standard.ink,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.id = id
            self.title = title
            self.pageCount = pageCount
            self.pageCountLabel = pageCountLabel ?? "\(pageCount) pages"
            self.coverColor = coverColor
            self.onTap = onTap
            self.style = style
        }
    }
}
