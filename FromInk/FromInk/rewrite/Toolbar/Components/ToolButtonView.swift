import SwiftUI

/// A single tool icon button in the toolbar rail.
/// Component view — no TCA imports.
///
struct ToolButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.foreground)
                .frame(width: model.width, height: model.height)
                .background(model.background)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(model.indicatorColor)
                        .frame(width: model.indicatorWidth)
                }
                .contentShape(Rectangle())
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
        let width: CGFloat
        let height: CGFloat
        let iconSize: CGFloat
        let foreground: Color
        let background: Color
        let indicatorColor: Color
        let indicatorWidth: CGFloat
    }
}

// MARK: - Model init

extension ToolButtonView.Model {
    init(
        id: String,
        icon: String,
        onTap: @escaping () -> Void,
        foreground: Color,
        background: Color,
        indicatorColor: Color,
        indicatorWidth: CGFloat,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.icon = icon
        self.onTap = onTap
        self.foreground = foreground
        self.background = background
        self.indicatorColor = indicatorColor
        self.indicatorWidth = indicatorWidth
        self.width = ds.layout.toolbarWidth
        self.height = ds.layout.toolbarButtonHeight
        self.iconSize = ds.layout.toolbarIconSize
    }
}
