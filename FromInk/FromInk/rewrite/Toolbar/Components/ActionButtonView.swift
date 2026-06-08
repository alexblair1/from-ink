import SwiftUI

/// An action icon button in a toolbar capsule (undo, redo, template,
/// settings, dispatch, bolt). Component view — no TCA imports.
///
/// Same round treatment as ToolButtonView but action buttons are never
/// "active" in the persistent sense — they fire a one-shot. No scale,
/// no shadow at rest. A pressed/hover treatment can be added later via
/// ButtonStyle if needed.
struct ActionButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.foreground)
                .frame(width: model.size, height: model.size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension ActionButtonView {
    struct Model {
        let id: String
        let icon: String
        let onTap: () -> Void
        let size: CGFloat
        let iconSize: CGFloat
        let foreground: Color
    }
}

// MARK: - Model init

extension ActionButtonView.Model {
    init(
        id: String,
        icon: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.icon = icon
        self.onTap = onTap
        self.size = ds.layout.toolbarCapsuleButtonSize
        self.iconSize = ds.layout.actionIconSize
        self.foreground = ds.colors.inkPure
    }
}
