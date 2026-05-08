import SwiftUI

/// Horizontal notebooks strip on the home screen.
/// Displays notebook spines in a scrollable row, sorted by last modified.
///
struct HomeNotebooksSection: View {
    let notebooks: [HomeScreen.Model.NotebookItem]
    let onNotebook: (UUID) -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                model: .init(title: "Notebooks", count: notebooks.count),
                trailing: {
                    MonoLabel("\(AppStrings.Home.lastModified) ↓", color: ds.colors.ink2)
                }
            )
            .padding(.horizontal, ds.spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(notebooks) { notebook in
                        notebookCard(notebook)
                    }
                }
                .padding(.horizontal, ds.spacing.lg)
                .padding(.vertical, ds.spacing.base)
            }
        }
    }

    private func notebookCard(_ notebook: HomeScreen.Model.NotebookItem) -> some View {
        Button { onNotebook(notebook.id) } label: {
            VStack(alignment: .leading, spacing: ds.spacing.sm) {
                // Notebook cover illustration
                ZStack {
                    ds.colors.paper

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
                        .background(ds.colors.paper)
                        // Bookmark line
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(notebook.coverColor.opacity(0.85))
                                .frame(width: 1.5)
                                .padding(.leading, ds.spacing.sm)
                        }
                    }
                    .padding(22)
                }
                .frame(width: 116, height: 154)
                .overlay(
                    Rectangle().strokeBorder(ds.colors.rule, lineWidth: 0.5)
                )

                // Title
                Text(notebook.title)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)
                    .lineLimit(1)
                    .frame(width: 116, alignment: .leading)

                // Subtitle
                MonoLabel(notebook.subtitle, size: 9, color: ds.colors.ink2)
                    .frame(width: 116, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
    }
}
