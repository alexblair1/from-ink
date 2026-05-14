import SwiftUI

/// The daily brief section: meta row, date, lede, counts bar, and expandable content.
/// Feature view — no TCA imports.
///
struct HomeDailyBrief: View {
    let model: Model
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Shared top — identical in collapsed and expanded
            BriefMetaRow(model: model.metaRow)
                .padding(.top, model.sectionSpacing)

            MastheadDateBlock(model: model.dateBlock)
                .padding(.horizontal, model.horizontalPadding)
                .padding(.top, model.innerSpacing)

            EditorsNoteSection(model: model.editorsNote)

            HairlineRule()
                .padding(.top, model.ruleSpacing)
                .padding(.horizontal, model.horizontalPadding)

            BriefCountsBar(model: model.countsBar)

            HairlineRule()
                .padding(.horizontal, model.horizontalPadding)

            // Expanded content — events calendar
            if isExpanded {
                highlightsSection

                BriefFooterActions(model: model.footerActions)

                HairlineRule()
                    .padding(.top, model.ruleSpacing)
                    .padding(.horizontal, model.horizontalPadding)
            }
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .padding(.horizontal, model.horizontalPadding)
    }
}

// MARK: - Model

extension HomeDailyBrief {
    struct Model {
        let metaRow: BriefMetaRow.Model
        let dateBlock: MastheadDateBlock.Model
        let lede: BriefLede.Model
        let countsBar: BriefCountsBar.Model
        let editorsNote: EditorsNoteSection.Model
        let highlights: [HighlightRow.Model]
        let footerActions: BriefFooterActions.Model
        let highlightsLabel: String
        let highlightsLabelColor: Color
        let horizontalPadding: CGFloat
        let sectionSpacing: CGFloat
        let innerSpacing: CGFloat
        let ruleSpacing: CGFloat
    }
}

// MARK: - Model init

extension HomeDailyBrief.Model {
    init(
        metaRow: BriefMetaRow.Model,
        dateBlock: MastheadDateBlock.Model,
        lede: BriefLede.Model,
        countsBar: BriefCountsBar.Model,
        editorsNote: EditorsNoteSection.Model,
        highlights: [HighlightRow.Model],
        footerActions: BriefFooterActions.Model,
        ds: DesignSystem = .standard
    ) {
        self.metaRow = metaRow
        self.dateBlock = dateBlock
        self.lede = lede
        self.countsBar = countsBar
        self.editorsNote = editorsNote
        self.highlights = highlights
        self.footerActions = footerActions
        self.highlightsLabel = AppStrings.Home.highlights
        self.highlightsLabelColor = ds.colors.ink2
        self.horizontalPadding = ds.spacing.lg
        self.sectionSpacing = ds.spacing.md
        self.innerSpacing = ds.spacing.sm
        self.ruleSpacing = ds.spacing.base
    }
}
