import SwiftUI

struct LassoMenuBar: View {
    var onTaskBrief: () -> Void = {}
    var onLink: () -> Void = {}
    var onCopyText: () -> Void = {}
    var onSearch: () -> Void = {}
    var onShare: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            menuButton(icon: "bolt.fill", tint: Color.bolt, action: onTaskBrief)
            divider
            menuButton(icon: "link", action: onLink)
            divider
            menuButton(icon: "doc.on.doc", action: onCopyText)
            divider
            menuButton(icon: "magnifyingglass", action: onSearch)
            divider
            menuButton(icon: "square.and.arrow.up", action: onShare)
        }
        .frame(height: 48)
        .fixedSize()
        .background(Color.surface)
        .overlay {
            Rectangle()
                .stroke(Color.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(width: 1)
    }

    @ViewBuilder
    private func menuButton(
        icon: String,
        tint: Color = Color.inkSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 54, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.canvas.ignoresSafeArea()
        .overlay { LassoMenuBar() }
}
