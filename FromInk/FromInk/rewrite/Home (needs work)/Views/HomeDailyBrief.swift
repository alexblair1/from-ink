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

            // Components handle their own horizontal padding
            BriefMetaRow(model: model.metaRow)
                .padding(.top, ds.spacing.md)

            MastheadDateBlock(model: model.dateBlock)
                .padding(.top, ds.spacing.sm)

            BriefLede(model: model.lede)

            // Bottom rule (collapsed) / separator before editor's note (expanded)
            HairlineRule()
                .padding(.top, ds.spacing.base)
                .padding(.horizontal, ds.spacing.lg)

            if isExpanded {
                EditorsNoteSection(model: model.editorsNote)

                HairlineRule()
                    .padding(.vertical, ds.spacing.base)
                    .padding(.horizontal, ds.spacing.lg)

                highlightsSection
                    .padding(.horizontal, ds.spacing.lg)

                BriefFooterActions(model: model.footerActions)

                HairlineRule()
                    .padding(.top, ds.spacing.base)
                    .padding(.horizontal, ds.spacing.lg)
            }
        }
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
