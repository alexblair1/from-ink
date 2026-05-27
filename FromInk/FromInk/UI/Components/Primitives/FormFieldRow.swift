import SwiftUI

/// Row used to display a labeled value that, when tapped, opens a
/// picker (calendar, date, list, priority, etc.). Mono label on the
/// leading edge, body text + chevron on the trailing edge. Used by
/// the event/reminder creation forms; also reusable anywhere we need
/// a settings-row-style picker affordance.
struct FormFieldRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: model.innerSpacing) {
                MonoLabel(model.label, color: model.labelColor)
                Spacer(minLength: model.innerSpacing)
                if !model.value.isEmpty {
                    Text(model.value)
                        .font(model.valueFont)
                        .foregroundStyle(model.valueColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .font(model.chevronFont)
                    .foregroundStyle(model.chevronColor)
            }
            .padding(.horizontal, model.horizontalPadding)
            .frame(height: model.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension FormFieldRow {
    struct Model {
        let label: String
        let value: String
        let onTap: () -> Void
        let labelColor: Color
        let valueFont: Font
        let valueColor: Color
        let chevronFont: Font
        let chevronColor: Color
        let horizontalPadding: CGFloat
        let innerSpacing: CGFloat
        let height: CGFloat
    }
}

extension FormFieldRow.Model {
    init(
        label: String,
        value: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        self.value = value
        self.onTap = onTap
        self.labelColor = ds.colors.ink3
        self.valueFont = ds.typography.body
        self.valueColor = ds.colors.ink
        self.chevronFont = ds.typography.caption
        self.chevronColor = ds.colors.ink2
        self.horizontalPadding = ds.spacing.base
        self.innerSpacing = ds.spacing.md
        self.height = ds.layout.hitTarget
    }
}
