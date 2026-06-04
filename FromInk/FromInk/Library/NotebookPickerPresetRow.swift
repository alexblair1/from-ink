import SwiftUI

/// Full-width tappable row in the picker's page-selection phase.
/// Used for the three terminal/disclosure affordances:
///   - "Last edited page" — chevron trailing
///   - "New page" — chevron trailing
///   - "Specific page" — disclosure trailing (rotates when expanded)
///
/// Component view: zero state, zero TCA, zero DesignSystem access.
///
struct NotebookPickerPresetRow: View {
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

                Spacer(minLength: 0)

                Image(systemName: model.trailingIconSystemName)
                    .font(.system(size: model.trailingIconSize, weight: .regular))
                    .foregroundStyle(model.trailingIconColor)
                    .rotationEffect(.degrees(model.trailingIconRotation))
            }
            .padding(.horizontal, model.horizontalPadding)
            .frame(minHeight: model.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension NotebookPickerPresetRow {
    struct Model: Equatable {
        let label: String
        let iconSystemName: String
        let trailingIconSystemName: String
        /// Rotation applied to the trailing icon — used by the
        /// "Specific page" disclosure to flip the chevron when
        /// expanded. 0 for non-disclosure rows.
        let trailingIconRotation: Double
        let onTap: () -> Void

        let iconColor: Color
        let labelColor: Color
        let trailingIconColor: Color
        let labelFont: Font

        let iconSize: CGFloat
        let iconFrame: CGFloat
        let trailingIconSize: CGFloat
        let spacing: CGFloat
        let horizontalPadding: CGFloat
        let minHeight: CGFloat

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.label == rhs.label
                && lhs.iconSystemName == rhs.iconSystemName
                && lhs.trailingIconSystemName == rhs.trailingIconSystemName
                && lhs.trailingIconRotation == rhs.trailingIconRotation
        }
    }
}

// MARK: - Model init

extension NotebookPickerPresetRow.Model {
    init(
        label: String,
        iconSystemName: String,
        trailingIconSystemName: String = "chevron.forward",
        trailingIconRotation: Double = 0,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        self.iconSystemName = iconSystemName
        self.trailingIconSystemName = trailingIconSystemName
        self.trailingIconRotation = trailingIconRotation
        self.onTap = onTap

        self.iconColor = ds.colors.ink
        self.labelColor = ds.colors.ink
        self.trailingIconColor = ds.colors.ink3
        self.labelFont = .system(.body, design: .serif)

        self.iconSize = 18
        self.iconFrame = ds.layout.iconFrame
        self.trailingIconSize = ds.layout.chevronSize
        self.spacing = ds.spacing.md
        self.horizontalPadding = ds.spacing.lg
        self.minHeight = ds.layout.hitTarget + 4
    }
}
