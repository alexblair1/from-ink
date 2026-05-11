import SwiftUI

/// A routed item row (calendar event or reminder) in the dispatch panel.
/// Component view — no TCA imports.
///
struct DispatchRoutedItemRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: model.innerSpacing) {
                Image(systemName: model.statusIcon)
                    .font(model.iconFont)
                    .foregroundStyle(model.statusColor)
                    .frame(width: model.iconFrame)

                Text(model.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)
                    .lineLimit(1)
                    .strikethrough(model.isStrikethrough)

                Spacer()

                Text(model.timeLabel)
                    .font(model.timeFont)
                    .foregroundStyle(model.secondaryColor)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(DispatchRowPressStyle())
        .disabled(model.isDisabled)
    }
}

// MARK: - Model

extension DispatchRoutedItemRow {
    struct Model {
        let id: String
        let title: String
        let timeLabel: String
        let statusIcon: String
        let isStrikethrough: Bool
        let isDisabled: Bool
        let onTap: () -> Void
        let iconFont: Font
        let titleFont: Font
        let timeFont: Font
        let titleColor: Color
        let statusColor: Color
        let secondaryColor: Color
        let iconFrame: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let innerSpacing: CGFloat
    }
}

// MARK: - Model init

extension DispatchRoutedItemRow.Model {
    init(
        item: DispatchRoutedItem,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = item.id.uuidString
        self.title = item.title
        self.timeLabel = item.routedAt.formatted(.relative(presentation: .named))
        self.statusIcon = item.isDeleted ? "xmark.circle" : "checkmark.circle"
        self.isStrikethrough = item.isDeleted
        self.isDisabled = item.isDeleted
        self.onTap = onTap
        self.iconFont = ds.typography.footnote
        self.titleFont = ds.typography.subheadline
        self.timeFont = ds.typography.caption
        self.titleColor = item.isDeleted ? ds.colors.ink3 : ds.colors.ink
        self.statusColor = item.isDeleted ? ds.colors.ink3 : ds.colors.ink2
        self.secondaryColor = ds.colors.ink2
        self.iconFrame = ds.layout.iconFrame
        self.horizontalPadding = ds.spacing.base
        self.verticalPadding = ds.spacing.md
        self.innerSpacing = ds.spacing.sm
    }
}
