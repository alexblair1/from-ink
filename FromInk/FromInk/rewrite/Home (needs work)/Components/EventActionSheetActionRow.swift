import SwiftUI

/// Full-width tappable row inside the event action sheet. Same visual
/// grammar as `NotebookPickerPresetRow` but reuses neither — the picker
/// row is sized for grid-row hits while this one carries action-sheet
/// emphasis (lighter, slightly tighter). Worth a separate component
/// rather than smuggling parameters into the picker row.
///
struct EventActionSheetActionRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: model.spacing) {
                Image(systemName: model.iconSystemName)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.iconFrame, height: model.iconFrame)

                Text(model.label)
                    .font(model.labelFont)
                    .foregroundStyle(model.labelColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, model.horizontalPadding)
            .frame(minHeight: model.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension EventActionSheetActionRow {
    struct Model: Equatable {
        let label: String
        let iconSystemName: String
        let onTap: () -> Void

        let iconColor: Color
        let labelColor: Color
        let labelFont: Font

        let iconSize: CGFloat
        let iconFrame: CGFloat
        let spacing: CGFloat
        let horizontalPadding: CGFloat
        let minHeight: CGFloat

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.label == rhs.label
                && lhs.iconSystemName == rhs.iconSystemName
        }
    }
}

// MARK: - Model init

extension EventActionSheetActionRow.Model {
    init(
        label: String,
        iconSystemName: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        self.iconSystemName = iconSystemName
        self.onTap = onTap

        self.iconColor = ds.colors.ink
        self.labelColor = ds.colors.ink
        self.labelFont = .system(.body, design: .serif)

        self.iconSize = 18
        self.iconFrame = ds.layout.iconFrame
        self.spacing = ds.spacing.md
        self.horizontalPadding = ds.spacing.lg
        self.minHeight = ds.layout.hitTarget + 4
    }
}
