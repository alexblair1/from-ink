import SwiftUI

/// Horizontal folders strip on the home screen.
/// Uses `SectionHeader` + horizontally scrolling folder cards.
///
struct HomeFoldersSection: View {
    let folders: [HomeScreen.Model.FolderItem]
    let onFolder: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Folders", count: folders.count)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(folders) { folder in
                        folderCard(folder)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            HairlineRule()
                .padding(.horizontal, 24)
        }
    }

    private func folderCard(_ folder: HomeScreen.Model.FolderItem) -> some View {
        Button { onFolder(folder.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: folder.icon)
                    .font(.system(size: 18, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color("ink/Ink"))

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color("ink/Ink"))
                        .lineLimit(1)

                    MonoLabel(
                        "\(folder.notebookCount) notebook\(folder.notebookCount == 1 ? "" : "s")",
                        size: 9,
                        color: Color("ink/Ink2")
                    )
                }
            }
            .padding(12)
            .frame(width: 148, height: 90)
            .overlay(
                Rectangle().strokeBorder(Color("ink/Rule"), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
    }
}
