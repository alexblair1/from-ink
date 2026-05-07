import SwiftUI
import SwiftData

struct FolderCard: View {
    let folder: Folder
    let notebookCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FolderCardContent(folder: folder, notebookCount: notebookCount)
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - Card content (reads pressed state from environment)

private struct FolderCardContent: View {
    let folder: Folder
    let notebookCount: Int
    @Environment(\.cardIsPressed) private var isPressed

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isPressed ? "folder.fill" : "folder")
                .font(.system(size: 18))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(notebookCount) notebook\(notebookCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.border)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isPressed ? Color.ink.opacity(0.04) : Color.surface)
        .overlay {
            Rectangle()
                .strokeBorder(isPressed ? Color.ink.opacity(0.3) : Color.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .animation(.linear(duration: 0.08), value: isPressed)
    }
}
