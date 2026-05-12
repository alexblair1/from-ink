import SwiftUI

/// The daily brief section: meta row, date, lede, and expandable editorial + highlights.
/// Feature view — no TCA imports.
///
struct HomeDailyBrief: View {
    let model: Model
    @Binding var isExpanded: Bool

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ds.colors.ink)
                .frame(height: 2)

            BriefMetaRow(model: model.metaRow)
                .padding(.top, ds.spacing.md)

            MastheadDateBlock(model: model.dateBlock)
                .padding(.top, ds.spacing.sm)

            BriefLede(model: model.lede)

            if isExpanded {
                EditorsNoteSection(model: model.editorsNote)

                HairlineRule()
                    .padding(.horizontal, ds.spacing.lg)
                    .padding(.vertical, ds.spacing.base)

                highlightsSection
                    .padding(.horizontal, ds.spacing.lg)

                BriefFooterActions(model: model.footerActions)
            }

            Rectangle()
                .fill(ds.colors.ink)
                .frame(height: ds.layout.borderWidth)
                .padding(.top, ds.spacing.base)
        }
        .padding(.horizontal, ds.spacing.lg)
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(AppStrings.Home.highlights, color: ds.colors.ink2)
                .padding(.bottom, ds.spacing.sm)

            ForEach(
                Array(model.highlights.enumerated()),
                id: \.element.id
            ) { index, highlight in
                if index > 0 {
                    HairlineRule()
                }
                HighlightRow(model: highlight)
            }
        }
    }
}

// MARK: - Model

extension HomeDailyBrief {
    struct Model {
        let metaRow: BriefMetaRow.Model
        let dateBlock: MastheadDateBlock.Model
        let lede: BriefLede.Model
        let editorsNote: EditorsNoteSection.Model
        let highlights: [HighlightRow.Model]
        let footerActions: BriefFooterActions.Model
    }
}
