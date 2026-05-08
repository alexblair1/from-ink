import SwiftUI

/// Folder card showing name, notebook count, and optional icon.
///
///     InkFolderCard(model: .init(
///         name: "Work",
///         notebookCount: 5,
///         onTap: { }
///     ))
///
struct InkFolderCard: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.icon)
                        .font(.system(size: 17, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color("ink/Ink2"))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color("ink/Ink"))
                            .lineLimit(1)

                        MonoLabel(
                            "\(model.notebookCount) notebook\(model.notebookCount == 1 ? "" : "s")",
                            color: Color("ink/Ink3")
                        )
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color("ink/Ink3"))
                }
                .padding(16)

                HairlineRule()
            }
            .background(Color("ink/Surface"))
        }
        .buttonStyle(.plain)
    }
}

extension InkFolderCard {
    struct Model {
        let id: UUID
        let name: String
        let notebookCount: Int
        let icon: String
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            name: String,
            notebookCount: Int = 0,
            icon: String = "folder",
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.name = name
            self.notebookCount = notebookCount
            self.icon = icon
            self.onTap = onTap
        }
    }
}
