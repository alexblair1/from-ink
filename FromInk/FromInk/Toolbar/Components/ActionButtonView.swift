import SwiftUI

/// An action icon button in the toolbar (undo, redo, template, settings).
/// Component view — no TCA imports.
///
struct ActionButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.foreground)
                .frame(width: model.width, height: model.height)
                .contentShape(Rectangle())
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
        let width: CGFloat
        let height: CGFloat
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
        self.width = ds.layout.toolbarWidth
        self.height = ds.layout.toolbarButtonHeight
        self.iconSize = ds.layout.toolbarIconSize
        self.foreground = ds.colors.ink2
    }
}
