import SwiftUI

/// A single tab button in the dispatch panel tab bar.
/// Component view — no TCA imports.
///
struct DispatchTabButton: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(model.background)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(model.indicatorColor)
                        .frame(height: model.indicatorHeight)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension DispatchTabButton {
    struct Model {
        let id: String
        let icon: String
        let onTap: () -> Void
        let iconSize: CGFloat
        let foreground: Color
        let background: Color
        let indicatorColor: Color
        let indicatorHeight: CGFloat
    }
}

// MARK: - Model init

extension DispatchTabButton.Model {
    init(
        id: String,
        icon: String,
        onTap: @escaping () -> Void,
        foreground: Color,
        background: Color,
        indicatorColor: Color,
        indicatorHeight: CGFloat,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.icon = icon
        self.onTap = onTap
        self.iconSize = ds.layout.tabIconSize
        self.foreground = foreground
        self.background = background
        self.indicatorColor = indicatorColor
        self.indicatorHeight = indicatorHeight
    }
}
