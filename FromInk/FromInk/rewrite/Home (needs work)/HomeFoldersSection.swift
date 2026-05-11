import SwiftUI

/// Horizontal folders strip on the home screen.
/// Uses `SectionHeader` + horizontally scrolling folder cards.
///
struct HomeFoldersSection: View {
    let folders: [HomeScreen.Model.FolderItem]
    let onFolder: (UUID) -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(model: .init(title: "Folders", count: folders.count))
                .padding(.horizontal, ds.spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ds.spacing.md) {
                    ForEach(folders) { folder in
                        folderCard(folder)
                    }
                }
                .padding(.horizontal, ds.spacing.lg)
                .padding(.vertical, ds.spacing.base)
            }

            HairlineRule()
                .padding(.horizontal, ds.spacing.lg)
        }
    }

    private func folderCard(_ folder: HomeScreen.Model.FolderItem) -> some View {
        Button { onFolder(folder.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: folder.icon)
                    .font(.system(size: 18, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ds.colors.ink)

                Spacer()

                VStack(alignment: .leading, spacing: ds.spacing.xxs) {
                    Text(folder.name)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(ds.colors.ink)
                        .lineLimit(1)

                    MonoLabel(
                        "\(folder.notebookCount) notebook\(folder.notebookCount == 1 ? "" : "s")",
                        size: 9,
                        color: ds.colors.ink2
                    )
                }
            }
            .padding(ds.spacing.md)
            .frame(width: 148, height: 90)
            .overlay(
                Rectangle().strokeBorder(ds.colors.rule, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
    }
}
