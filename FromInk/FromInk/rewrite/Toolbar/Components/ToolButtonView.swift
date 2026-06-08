import SwiftUI

/// A single tool icon button in a toolbar capsule.
/// Component view — no TCA imports.
///
/// Round (50% radius), scale-on-active treatment per the floating
/// capsule design. The view is pure: scale and shadow are pre-resolved
/// flat fields on the Model; the adapter sets them based on active
/// state. No `isActive` conditional in the view body.
struct ToolButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.foreground)
                .frame(width: model.size, height: model.size)
                .background(
                    Circle().fill(model.background)
                )
                .scaleEffect(model.scale)
                .shadow(
                    color: model.shadowColor,
                    radius: model.shadowRadius,
                    x: 0,
                    y: model.shadowY
                )
                .animation(model.animation, value: model.foreground)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension ToolButtonView {
    struct Model {
        let id: String
        let icon: String
        let onTap: () -> Void
        let size: CGFloat
        let iconSize: CGFloat
        let foreground: Color
        let background: Color
        let scale: CGFloat
        let shadowColor: Color
        let shadowRadius: CGFloat
        let shadowY: CGFloat
        let animation: Animation
    }
}

// MARK: - Model init

extension ToolButtonView.Model {
    init(
        id: String,
        icon: String,
        onTap: @escaping () -> Void,
        isActive: Bool,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.icon = icon
        self.onTap = onTap
        self.size = ds.layout.toolbarCapsuleButtonSize
        self.iconSize = ds.layout.toolbarIconSize
        self.foreground = isActive ? ds.colors.paperPure : ds.colors.ink2
        self.background = isActive ? ds.colors.inkPure : .clear
        self.scale = isActive ? ds.layout.toolbarCapsuleActiveScale : 1.0
        self.shadowColor = isActive ? ds.shadow.toolbarActiveButton.color : .clear
        self.shadowRadius = isActive ? ds.shadow.toolbarActiveButton.radius : 0
        self.shadowY = isActive ? ds.shadow.toolbarActiveButton.y : 0
        self.animation = ds.animation.fast
    }
}
