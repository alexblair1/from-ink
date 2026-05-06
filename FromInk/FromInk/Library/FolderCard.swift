import SwiftUI
import SwiftData

struct FolderCard: View {
    let folder: Folder
    let notebookCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)

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
            .background(Color.surface)
            .overlay {
                Rectangle()
                    .strokeBorder(Color.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
    }
}
