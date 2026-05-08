import SwiftUI

/// SF Symbol in a tappable hit target. Monochrome, ink-tinted.
///
///     IconButton("magnifyingglass", action: search)
///     IconButton("plus", size: .tabBar, action: add)
///     IconButton("pencil", size: .toolbar, color: ColorTokens.standard.ink2, action: edit)
///
struct IconButton: View {

    let systemName: String
    let size: Size
    let color: Color
    let style: Style
    let action: () -> Void

    init(
        _ systemName: String,
        size: Size = .body,
        color: Color = ColorTokens.standard.ink,
        style: Style = .standard,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.color = color
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size.pointSize, weight: size.weight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(minWidth: style.hitTarget, minHeight: style.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Style

extension IconButton {
    struct Style {
        let hitTarget: CGFloat

        static let standard = Style(
            hitTarget: LayoutTokens.standard.hitTarget
        )
    }
}

// MARK: - Size

extension IconButton {
    enum Size {
        /// 17pt — Nav bar trailing, list row leading.
        case body
        /// 22pt — Toolbar / pen tray.
        case toolbar
        /// 25pt — Tab bar.
        case tabBar
        /// 13pt — Inline metadata.
        case footnote

        var pointSize: CGFloat {
            switch self {
            case .body: 17
            case .toolbar: 22
            case .tabBar: 25
            case .footnote: 13
            }
        }

        var weight: Font.Weight {
            switch self {
            case .tabBar: .medium
            default: .regular
            }
        }
    }
}
