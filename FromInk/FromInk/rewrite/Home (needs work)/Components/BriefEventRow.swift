import SwiftUI

/// One row in the Calendar tab's expanded body — a single event.
///
/// Layout: [ time | title + where + optional notebook link | duration ]
///         time column 56pt, duration right-aligned, title flexible.
///
/// Stateless. The notebook-link sub-row is shown iff `notebookLink` is
/// non-nil; the "Next" pill is shown iff `isNext`.
///
struct BriefEventRow: View {
    let model: Model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: model.columnGap) {
            Text(model.time)
                .font(.system(size: model.timeFontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(model.timeColor)
                // 1-line + scale-floor so locale times like "12:00 AM" or
                // 24-hour "13:30" don't wrap inside the fixed-width time
                // column. Mono kerning is already tight; allowsTightening
                // shaves a couple more pixels before scaling kicks in.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .frame(width: model.timeColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: model.titleSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.title)
                        .font(.system(size: model.titleFontSize, weight: .regular, design: .serif))
                        .foregroundStyle(model.titleColor)
                        .lineLimit(2)

                    if model.isNext {
                        Text(model.nextPillLabel)
                            .font(.system(size: model.pillFontSize, weight: .medium, design: .monospaced))
                            .tracking(model.pillTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(model.pillForeground)
                            .padding(.horizontal, model.pillHorizontalPadding)
                            .padding(.vertical, model.pillVerticalPadding)
                            .background(model.pillBackground)
                    }
                }

                if let location = model.location {
                    Text(location)
                        .font(.system(size: model.locationFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(model.locationColor)
                }

                if let notebook = model.notebookLink {
                    notebookLinkView(notebook)
                }
            }

            Spacer(minLength: 0)

            Text(model.duration)
                .font(.system(size: model.durationFontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(model.durationColor)
        }
        .padding(.vertical, model.verticalPadding)
        .overlay(alignment: .bottom) {
            if !model.hidesBottomRule {
                Rectangle()
                    .fill(model.ruleColor)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func notebookLinkView(_ link: Model.NotebookLink) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(model.notebookLinkColor)
            Text(link.notebookTitle)
                .italic()
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(model.titleColor)
            Text(link.pageLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(model.notebookLinkColor)
            Image(systemName: "chevron.forward")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(model.notebookLinkColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .stroke(model.notebookLinkBorder, lineWidth: 1)
        )
        .padding(.top, 4)
    }
}

// MARK: - Model

extension BriefEventRow {
    struct Model: Identifiable {
        struct NotebookLink: Equatable {
            let notebookTitle: String
            let pageLabel: String   // "p.7" — localized in the wiring view
            let notebookID: UUID
            let pageIndex: Int
        }

        let id: String
        let time: String           // "9:30" — locale-formatted by the wiring view
        let title: String
        let location: String?
        let duration: String       // "30m" — locale-formatted
        let isNext: Bool
        let notebookLink: NotebookLink?
        /// True for the last row in a list so the row's bottom rule is
        /// suppressed. The section header below already supplies its own
        /// top rule; stacking both produced a visible "double divider."
        let hidesBottomRule: Bool

        let nextPillLabel: String
        let columnGap: CGFloat
        let timeColumnWidth: CGFloat
        let titleSpacing: CGFloat
        let timeFontSize: CGFloat
        let titleFontSize: CGFloat
        let locationFontSize: CGFloat
        let durationFontSize: CGFloat
        let pillFontSize: CGFloat
        let pillTracking: CGFloat
        let pillHorizontalPadding: CGFloat
        let pillVerticalPadding: CGFloat
        let verticalPadding: CGFloat

        let timeColor: Color
        let titleColor: Color
        let locationColor: Color
        let durationColor: Color
        let pillForeground: Color
        let pillBackground: Color
        let notebookLinkColor: Color
        let notebookLinkBorder: Color
        let ruleColor: Color
    }
}

// MARK: - Model init

extension BriefEventRow.Model {
    init(
        id: String,
        time: String,
        title: String,
        location: String?,
        duration: String,
        isNext: Bool,
        nextPillLabel: String,
        notebookLink: NotebookLink?,
        hidesBottomRule: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.location = location
        self.duration = duration
        self.isNext = isNext
        self.notebookLink = notebookLink
        self.hidesBottomRule = hidesBottomRule

        self.nextPillLabel = nextPillLabel
        self.columnGap = 18
        // 64pt instead of the 56pt spec — fits English "12:00 AM" without
        // forcing the scale floor to kick in, while staying close to the
        // editorial proportions. Locales with shorter time formats
        // ("9:30") still left-align inside the column.
        self.timeColumnWidth = 64
        self.titleSpacing = 4
        self.timeFontSize = 12
        self.titleFontSize = 18
        self.locationFontSize = 11
        self.durationFontSize = 11
        self.pillFontSize = 9.5
        self.pillTracking = 1.4
        self.pillHorizontalPadding = 7
        self.pillVerticalPadding = 4
        // 14pt to match the React spec's `padding: 14px 0` for event rows.
        // The design system's .sm (8pt) was too tight.
        self.verticalPadding = 14

        self.timeColor = ds.colors.ink2
        self.titleColor = ds.colors.ink
        self.locationColor = ds.colors.ink2
        self.durationColor = ds.colors.ink2
        self.pillForeground = ds.colors.paperOnInk
        self.pillBackground = ds.colors.ink
        self.notebookLinkColor = ds.colors.ink2
        self.notebookLinkBorder = ds.colors.rule
        self.ruleColor = ds.colors.rule
    }
}
