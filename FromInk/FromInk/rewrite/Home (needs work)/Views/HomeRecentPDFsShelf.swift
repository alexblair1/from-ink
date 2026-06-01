import SwiftUI

/// Horizontal recent-PDFs shelf — section header + scrollable cards.
/// Sibling of `HomeNotebookShelf`; the visual language (card dimensions,
/// outer padding, scroll behavior) matches deliberately so the two
/// sections read as parallel surfaces. The card itself differs: PDFs
/// show their cover thumbnail rather than a notebook spine, and the
/// secondary metadata is page count instead of a relative time label.
///
/// Feature view — no TCA imports.
struct HomeRecentPDFsShelf: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                model: .init(
                    title: model.sectionTitle,
                    count: model.pdfCount,
                    showsTopRule: true
                ),
                trailing: {
                    MonoLabel(model.sortLabel, color: model.sortLabelColor)
                }
            )
            .padding(.horizontal, model.outerPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: model.cardSpacing) {
                    ForEach(model.pdfs) { pdf in
                        pdfCard(pdf)
                    }
                }
                .padding(.horizontal, model.outerPadding)
                .padding(.vertical, model.scrollVerticalPadding)
            }
        }
    }

    private func pdfCard(_ pdf: PDFCardModel) -> some View {
        Button { pdf.onTap() } label: {
            VStack(alignment: .leading, spacing: model.cardInnerSpacing) {
                cover(pdf)
                    .frame(width: model.cardWidth, height: model.cardHeight)
                    .overlay(
                        Rectangle().strokeBorder(
                            model.cardBorderColor,
                            lineWidth: model.cardBorderWidth
                        )
                    )

                Text(pdf.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)
                    .lineLimit(1)
                    .frame(width: model.cardWidth, alignment: .leading)

                MonoLabel(pdf.pagesLabel, size: 9, color: model.pagesLabelColor)
                    .frame(width: model.cardWidth, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
    }

    /// Renders the cover thumbnail when present, with a paper-coloured
    /// placeholder when the import didn't capture one (PDFs whose first
    /// page rendered nil — rare but possible for damaged sources).
    @ViewBuilder
    private func cover(_ pdf: PDFCardModel) -> some View {
        if let data = pdf.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            model.coverPlaceholderColor
        }
    }
}

// MARK: - Model

extension HomeRecentPDFsShelf {
    struct Model {
        let sectionTitle: String
        let pdfCount: Int
        let sortLabel: String
        let pdfs: [PDFCardModel]
        let cardSpacing: CGFloat
        let cardInnerSpacing: CGFloat
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let cardBorderWidth: CGFloat
        let titleFont: Font
        let outerPadding: CGFloat
        let scrollVerticalPadding: CGFloat
        let sortLabelColor: Color
        let cardBorderColor: Color
        let coverPlaceholderColor: Color
        let titleColor: Color
        let pagesLabelColor: Color
    }

    struct PDFCardModel: Identifiable {
        let id: UUID
        let title: String
        let pagesLabel: String
        let thumbnailData: Data?
        let onTap: () -> Void
    }
}

// MARK: - Model init

extension HomeRecentPDFsShelf.Model {
    init(
        pdfs: [HomeRecentPDFsShelf.PDFCardModel],
        ds: DesignSystem = .standard
    ) {
        self.sectionTitle = AppStrings.Home.recentPDFs
        self.pdfCount = pdfs.count
        self.sortLabel = "\(AppStrings.Home.lastModified) ↓"
        self.pdfs = pdfs
        self.cardSpacing = ds.layout.notebookCardSpacing
        self.cardInnerSpacing = ds.spacing.sm
        self.cardWidth = ds.layout.notebookCardWidth
        self.cardHeight = ds.layout.notebookCardHeight
        self.cardBorderWidth = ds.layout.borderWidth
        self.titleFont = ds.typography.cardTitle
        self.outerPadding = ds.spacing.lg
        self.scrollVerticalPadding = ds.spacing.base
        self.sortLabelColor = ds.colors.ink2
        self.cardBorderColor = ds.colors.rule
        self.coverPlaceholderColor = ds.colors.paper
        self.titleColor = ds.colors.ink
        self.pagesLabelColor = ds.colors.ink2
    }
}
