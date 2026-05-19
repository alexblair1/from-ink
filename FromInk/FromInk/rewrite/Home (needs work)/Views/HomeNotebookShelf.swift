import SwiftUI

/// Horizontal notebook shelf: section header + scrollable notebook spines.
/// Feature view — no TCA imports.
///
struct HomeNotebookShelf: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                model: .init(
                    title: model.sectionTitle,
                    count: model.notebookCount,
                    // The preceding brief tab body's last row already
                    // contributes its own bottom rule; suppress the
                    // SectionHeader's HairlineRule so the two don't
                    // stack as a double divider.
                    showsTopRule: false
                ),
                trailing: {
                    MonoLabel(model.sortLabel, color: model.sortLabelColor)
                }
            )
            .padding(.horizontal, model.outerPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: model.cardSpacing) {
                    ForEach(model.notebooks) { notebook in
                        notebookCard(notebook)
                    }
                }
                .padding(.horizontal, model.outerPadding)
                .padding(.vertical, model.scrollVerticalPadding)
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
                        .fill(model.spineColor)
                        .frame(width: model.spineWidth)

                    model.cardFillColor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: model.cardWidth, height: model.cardHeight)
                .overlay(
                    Rectangle().strokeBorder(
                        model.cardBorderColor,
                        lineWidth: model.cardBorderWidth
                    )
                )

                Text(notebook.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)
                    .lineLimit(1)
                    .frame(width: model.cardWidth, alignment: .leading)

                MonoLabel(notebook.timeLabel, size: 9, color: model.timeLabelColor)
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
        let outerPadding: CGFloat
        let scrollVerticalPadding: CGFloat
        let sortLabelColor: Color
        let spineColor: Color
        let cardFillColor: Color
        let cardBorderColor: Color
        let titleColor: Color
        let timeLabelColor: Color
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
        self.cardSpacing = ds.layout.notebookCardSpacing
        self.cardInnerSpacing = ds.spacing.sm
        self.cardWidth = ds.layout.notebookCardWidth
        self.cardHeight = ds.layout.notebookCardHeight
        self.cardBorderWidth = ds.layout.borderWidth
        self.spineWidth = ds.layout.notebookSpineWidth
        self.titleFont = ds.typography.cardTitle
        self.outerPadding = ds.spacing.lg
        self.scrollVerticalPadding = ds.spacing.base
        self.sortLabelColor = ds.colors.ink2
        self.spineColor = ds.colors.ink
        self.cardFillColor = ds.colors.paper
        self.cardBorderColor = ds.colors.rule
        self.titleColor = ds.colors.ink
        self.timeLabelColor = ds.colors.ink2
    }
}
