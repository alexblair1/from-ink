import SwiftUI

/// Horizontal notebooks strip on the home screen.
/// Displays notebook spines in a scrollable row, sorted by last modified.
///
struct HomeNotebooksSection: View {
    let notebooks: [HomeScreen.Model.NotebookItem]
    let onNotebook: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                "Notebooks",
                count: notebooks.count,
                trailing: {
                    MonoLabel("Last modified ↓", color: Color("ink/Ink2"))
                }
            )
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(notebooks) { notebook in
                        notebookCard(notebook)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private func notebookCard(_ notebook: HomeScreen.Model.NotebookItem) -> some View {
        Button { onNotebook(notebook.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Notebook cover illustration
                ZStack {
                    Color("ink/Paper")

                    // Spine + page illustration
                    HStack(spacing: 0) {
                        // Spine
                        Rectangle()
                            .fill(notebook.coverColor)
                            .frame(width: 8)
                        // Page area
                        VStack {
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color("ink/Paper"))
                        // Bookmark line
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(notebook.coverColor.opacity(0.85))
                                .frame(width: 1.5)
                                .padding(.leading, 10)
                        }
                    }
                    .padding(22)
                }
                .frame(width: 116, height: 154)
                .overlay(
                    Rectangle().strokeBorder(Color("ink/Rule"), lineWidth: 0.5)
                )

                // Title
                Text(notebook.title)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(Color("ink/Ink"))
                    .lineLimit(1)
                    .frame(width: 116, alignment: .leading)

                // Subtitle
                MonoLabel(notebook.subtitle, size: 9, color: Color("ink/Ink2"))
                    .frame(width: 116, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
    }
}
