import SwiftUI

/// Reminder row with completion toggle, title, due info, and list indicator.
///
///     ReminderRow(model: .init(
///         title: "Buy groceries",
///         dueDate: "Today, 5:00 PM",
///         isCompleted: false,
///         onToggle: { },
///         onTap: { }
///     ))
///
struct ReminderRow: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: model.style.innerSpacing) {
                Button(action: model.onToggle) {
                    Image(systemName: model.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(model.style.checkboxFont)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            model.isCompleted
                                ? model.style.completedColor
                                : model.listColor
                        )
                        .frame(
                            width: model.style.iconFrame,
                            height: model.style.iconFrame
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: model.onTap) {
                    VStack(alignment: .leading, spacing: model.style.metadataSpacing) {
                        Text(model.title)
                            .font(model.style.titleFont)
                            .foregroundStyle(
                                model.isCompleted
                                    ? model.style.completedColor
                                    : model.style.titleColor
                            )
                            .strikethrough(model.isCompleted)
                            .lineLimit(2)

                        HStack(spacing: model.style.metadataInnerSpacing) {
                            if let dueDate = model.dueDate {
                                MonoLabel(dueDate)
                            }
                            if let listName = model.listName {
                                MonoLabel(
                                    "· \(listName)",
                                    color: model.style.completedColor
                                )
                            }
                        }
                    }

                    Spacer()
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, model.style.verticalPadding)
            .padding(.horizontal, model.style.horizontalPadding)

            HairlineRule()
        }
    }
}

extension ReminderRow {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let completedColor: Color
        let checkboxFont: Font
        let innerSpacing: CGFloat
        let metadataSpacing: CGFloat
        let metadataInnerSpacing: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
        let iconFrame: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.body,
            titleColor: ColorTokens.standard.ink,
            completedColor: ColorTokens.standard.ink3,
            checkboxFont: .system(size: 22, weight: .regular),
            innerSpacing: SpacingScale.standard.md,
            metadataSpacing: SpacingScale.standard.xs,
            metadataInnerSpacing: SpacingScale.standard.sm,
            verticalPadding: SpacingScale.standard.md,
            horizontalPadding: SpacingScale.standard.base,
            iconFrame: LayoutTokens.standard.iconFrame
        )
    }

    struct Model {
        let id: UUID
        let title: String
        let dueDate: String?
        let listName: String?
        let listColor: Color
        let isCompleted: Bool
        let onToggle: () -> Void
        let onTap: () -> Void
        let style: Style

        init(
            id: UUID = UUID(),
            title: String,
            dueDate: String? = nil,
            listName: String? = nil,
            listColor: Color = ColorTokens.standard.ink,
            isCompleted: Bool = false,
            onToggle: @escaping () -> Void,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.id = id
            self.title = title
            self.dueDate = dueDate
            self.listName = listName
            self.listColor = listColor
            self.isCompleted = isCompleted
            self.onToggle = onToggle
            self.onTap = onTap
            self.style = style
        }
    }
}
