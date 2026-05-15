import SwiftUI

/// A single highlight row: mono category, icon + serif title + italic time, trailing badge.
/// Component view — no TCA imports.
///
struct HighlightRow: View {
    let model: Model

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: model.innerSpacing) {
                MonoLabel(model.category, color: model.categoryColor)

                HStack(spacing: model.iconSpacing) {
                    Image(systemName: model.icon)
                        .font(model.iconFont)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.iconColor)
                        .frame(width: model.iconFrame)

                    (
                        Text(model.title)
                            .font(model.titleFont)
                            .foregroundStyle(model.titleColor)
                        +
                        Text(model.timeSeparator)
                            .font(model.titleFont)
                            .foregroundStyle(model.timeColor)
                        +
                        Text(model.time)
                            .font(model.titleFont)
                            .italic()
                            .foregroundStyle(model.timeColor)
                    )
                }
            }

            Spacer()

            if !model.trailingBadge.isEmpty {
                MonoLabel(model.trailingBadge, color: model.badgeColor)
                    .padding(.top, model.badgeTopPadding)
            }
        }
        .padding(.vertical, model.verticalPadding)
    }
}

// MARK: - Model

extension HighlightRow {
    struct Model {
        let id: String
        let category: String
        let icon: String
        let title: String
        let time: String
        let timeSeparator: String
        let trailingBadge: String
        let categoryColor: Color
        let iconColor: Color
        let iconFont: Font
        let iconFrame: CGFloat
        let iconSpacing: CGFloat
        let titleFont: Font
        let titleColor: Color
        let timeColor: Color
        let badgeColor: Color
        let badgeTopPadding: CGFloat
        let verticalPadding: CGFloat
        let innerSpacing: CGFloat
    }
}

// MARK: - Model init

extension HighlightRow.Model {
    init(
        id: String,
        category: String,
        icon: String,
        title: String,
        time: String,
        trailingBadge: String = "",
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.category = category
        self.icon = icon
        self.title = title
        self.time = time
        self.timeSeparator = "  \u{2014}  "
        self.trailingBadge = trailingBadge
        self.categoryColor = ds.colors.ink2
        self.iconColor = ds.colors.ink
        self.iconFont = ds.typography.footnote
        self.iconFrame = ds.layout.iconFrame
        self.iconSpacing = ds.spacing.sm
        self.titleFont = ds.typography.editorBody
        self.titleColor = ds.colors.ink
        self.timeColor = ds.colors.ink2
        self.badgeColor = ds.colors.ink2
        self.badgeTopPadding = ds.spacing.base
        self.verticalPadding = ds.spacing.sm
        self.innerSpacing = ds.spacing.xxs
    }
}
