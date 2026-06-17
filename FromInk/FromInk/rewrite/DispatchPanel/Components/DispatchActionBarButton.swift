import SwiftUI

/// Bordered "+ Add …" action button pinned to the bottom of the
/// dispatch panel. Shown for tabs whose items can be created from the
/// menu (links, calendar, reminders) — not headers.
/// Component view — no TCA imports.
///
struct DispatchActionBarButton: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: model.innerSpacing) {
                Image(systemName: "plus")
                    .font(.system(size: model.iconSize, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                Text(model.label)
                    .font(model.labelFont)
                    .tracking(model.labelTracking)
                    .textCase(.uppercase)
            }
            .foregroundStyle(model.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: model.buttonHeight)
            .overlay(
                RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
                    .strokeBorder(model.borderColor, lineWidth: model.borderWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.topPadding)
        .padding(.bottom, model.bottomPadding)
    }
}

// MARK: - Model

extension DispatchActionBarButton {
    struct Model {
        let label: String
        let onTap: () -> Void
        let foreground: Color
        let borderColor: Color
        let labelFont: Font
        let labelTracking: CGFloat
        let iconSize: CGFloat
        let buttonHeight: CGFloat
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let innerSpacing: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }
}

// MARK: - Model init

extension DispatchActionBarButton.Model {
    init(
        label: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        self.onTap = onTap
        self.foreground = ds.colors.ink2
        self.borderColor = ds.colors.rule
        self.labelFont = ds.typography.monoLabel
        self.labelTracking = ds.typography.monoLinkTracking
        self.iconSize = ds.layout.actionIconSize
        self.buttonHeight = ds.layout.dialogActionHeight
        self.cornerRadius = ds.cornerRadius.row
        self.borderWidth = ds.layout.borderWidth
        self.innerSpacing = ds.spacing.sm
        self.horizontalPadding = ds.spacing.base
        self.topPadding = ds.spacing.md
        self.bottomPadding = ds.spacing.base
    }
}
