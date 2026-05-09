import SwiftUI

/// A single tool icon button in the toolbar rail.
/// Component view — no TCA imports.
///
struct ToolButtonView: View {
    let model: Model

    var body: some View {
        Button {
            model.onTap()
        } label: {
            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.isActive ? model.activeForeground : model.inactiveForeground)
                .frame(width: model.width, height: model.height)
                .background(model.isActive ? model.activeBackground : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { model.onDoubleTap() }
        )
    }
}

// MARK: - Model

extension ToolButtonView {
    struct Model {
        let id: String
        let icon: String
        let isActive: Bool
        let onTap: () -> Void
        let onDoubleTap: () -> Void
        let width: CGFloat
        let height: CGFloat
        let iconSize: CGFloat
        let activeForeground: Color
        let inactiveForeground: Color
        let activeBackground: Color
    }
}

// MARK: - Model init

extension ToolButtonView.Model {
    init(
        id: String,
        icon: String,
        isActive: Bool,
        onTap: @escaping () -> Void,
        onDoubleTap: @escaping () -> Void = {},
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.icon = icon
        self.isActive = isActive
        self.onTap = onTap
        self.onDoubleTap = onDoubleTap
        self.width = ds.layout.toolbarWidth
        self.height = ds.layout.toolbarButtonHeight
        self.iconSize = ds.layout.toolbarIconSize
        self.activeForeground = ds.colors.paperOnInk
        self.inactiveForeground = ds.colors.ink2
        self.activeBackground = ds.colors.ink
    }
}
