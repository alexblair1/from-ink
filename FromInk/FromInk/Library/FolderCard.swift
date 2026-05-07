import SwiftUI
import SwiftData

struct FolderCard: View {
    let folder: Folder
    let notebookCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ink)

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text("\(notebookCount) notebook\(notebookCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(14)
            .frame(width: 150, height: 110)
            .background(Color.surface)
            .overlay {
                Rectangle().strokeBorder(Color.border, lineWidth: 1)
            }
        }
        .buttonStyle(CardButtonStyle())
    }
}
