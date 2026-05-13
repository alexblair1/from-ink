import SwiftUI

/// Horizontal notebook shelf: section header + scrollable notebook spines.
/// Feature view — no TCA imports.
///
struct HomeNotebookShelf: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                model: .init(
                    title: model.sectionTitle,
                    count: model.notebookCount
                ),
                trailing: {
                    MonoLabel(model.sortLabel, color: ds.colors.ink2)
                }
            )
            .padding(.horizontal, ds.spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: model.cardSpacing) {
                    ForEach(model.notebooks) { notebook in
                        notebookCard(notebook)
                    }
                }
                .padding(.horizontal, ds.spacing.lg)
                .padding(.vertical, ds.spacing.base)
            }
        }
    }

    private func notebookCard(
        _ notebook: NotebookCardModel
    ) -> some View {
        Button { notebook.onTap() } label: {
            VStack(alignment: .leading, spacing: model.cardInnerSpacing) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(ds.colors.ink)
                        .frame(width: model.spineWidth)

                    ds.colors.paper
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: model.cardWidth, height: model.cardHeight)
                .overlay(
                    Rectangle().strokeBorder(
                        ds.colors.rule,
                        lineWidth: model.cardBorderWidth
                    )
                )

                Text(notebook.title)
                    .font(model.titleFont)
                    .foregroundStyle(ds.colors.ink)
                    .lineLimit(1)
                    .frame(width: model.cardWidth, alignment: .leading)

                MonoLabel(notebook.timeLabel, size: 9, color: ds.colors.ink2)
                    .frame(width: model.cardWidth, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
    }
}

// MARK: - Model

extension HomeNotebookShelf {
    struct Model {
        let sectionTitle: String
        let notebookCount: Int
        let sortLabel: String
        let notebooks: [NotebookCardModel]
        let cardSpacing: CGFloat
        let cardInnerSpacing: CGFloat
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let cardBorderWidth: CGFloat
        let spineWidth: CGFloat
        let titleFont: Font
    }

    struct NotebookCardModel: Identifiable {
        let id: UUID
        let title: String
        let timeLabel: String
        let onTap: () -> Void
    }
}

// MARK: - Model init

extension HomeNotebookShelf.Model {
    init(
        notebooks: [HomeNotebookShelf.NotebookCardModel],
        ds: DesignSystem = .standard
    ) {
        self.sectionTitle = AppStrings.Home.notebooks
        self.notebookCount = notebooks.count
        self.sortLabel = "\(AppStrings.Home.lastModified) ↓"
        self.notebooks = notebooks
        self.cardSpacing = 18
        self.cardInnerSpacing = ds.spacing.sm
        self.cardWidth = 116
        self.cardHeight = 154
        self.cardBorderWidth = ds.layout.borderWidth
        self.spineWidth = 6
        self.titleFont = .system(size: 13, weight: .regular, design: .serif)
    }
}
