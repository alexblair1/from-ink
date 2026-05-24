import SwiftUI

struct LinkIndicator: View {
    let link: NoteLinkSnapshot
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dashed selection border around the linked region
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: link.rect.width, height: link.rect.height)

            // Link badge — tap to open, long press for edit/delete
            Button(action: onTap) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.surface)
                    .frame(width: 28, height: 28)
                    .background(Color.inkSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .contextMenu {
                Button { onEdit() } label: {
                    Label("Edit Link", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Remove Link", systemImage: "trash")
                }
            }
        }
        .allowsHitTesting(true)
    }
}
