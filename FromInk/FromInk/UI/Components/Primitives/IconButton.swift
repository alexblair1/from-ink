import SwiftUI

/// SF Symbol in a tappable hit target. Monochrome, ink-tinted.
///
///     IconButton("magnifyingglass", action: search)
///     IconButton("plus", size: .tabBar, action: add)
///     IconButton("pencil", size: .toolbar, color: Color("ink/Ink2"), action: edit)
///
struct IconButton: View {

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

        var minHitTarget: CGFloat { 44 }
    }

    let systemName: String
    let size: Size
    let color: Color
    let action: () -> Void

    init(
        _ systemName: String,
        size: Size = .body,
        color: Color = Color("ink/Ink"),
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size.pointSize, weight: size.weight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(minWidth: size.minHitTarget, minHeight: size.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
