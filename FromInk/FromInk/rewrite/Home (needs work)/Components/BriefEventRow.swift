import SwiftUI

/// One row in the Calendar tab's expanded body — a single event.
///
/// Layout: [ bar | time | title + where + optional notebook link | duration ]
/// The leading bar always reserves its column (so in-progress and non-
/// in-progress events stay vertically aligned); the bar paints visibly
/// only when `isInProgress` is true. Animation is owned by the
/// `InProgressBar` component, which honors `accessibilityReduceMotion`.
///
/// The previous "Next up" pill was removed in favor of this leading
/// indicator. Per-event in-progress state has no event-to-event
/// coupling (each event evaluates its own [startDate, endDate) window
/// independently), so overlapping in-progress events naturally
/// surface as multiple blinking bars.
///
/// Stateless. The notebook-link sub-row is shown iff `notebookLink` is
/// non-nil.
///
struct BriefEventRow: View {
    let model: Model

    var body: some View {
        // Outer HStack uses `.top` alignment so the bar fills the
        // full row height while the inner content keeps its
        // `.firstTextBaseline` alignment intact.
        HStack(alignment: .top, spacing: 0) {
            InProgressBar(
                isActive: model.isInProgress,
                color: model.barColor,
                width: model.barWidth
            )

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
                    Text(model.title)
                        .font(.system(size: model.titleFontSize, weight: .regular, design: .serif))
                        .foregroundStyle(model.titleColor)
                        .lineLimit(2)

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

                badgeView
            }
            .padding(.leading, model.barTrailingGap)
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

    /// Trailing badge — either a localized text label ("In 30 m", "Now",
    /// "All day") or a SF Symbol (checkmark for passed events). The
    /// adapter decides which based on raw event timing against
    /// `state.nowTick`, so the badge stays in sync with the in-progress
    /// bar's predicate.
    @ViewBuilder
    private var badgeView: some View {
        switch model.duration {
        case .text(let label):
            Text(label)
                .font(.system(size: model.durationFontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(model.durationColor)
        case .icon(let systemName, let color, let accessibilityLabel):
            Image(systemName: systemName)
                .font(.system(size: model.iconBadgeSize, weight: .regular))
                .foregroundStyle(color)
                .accessibilityLabel(accessibilityLabel)
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
        /// Trailing badge — either a localized time-relative label
        /// ("In 30 m", "Now", "All day") or a SF Symbol (checkmark
        /// for passed events). Field name kept as `duration` for
        /// continuity with the existing layout slot; the contents
        /// model the same semantic ("how does this event sit relative
        /// to now") through a richer type.
        let duration: Badge
        /// Whether this event is happening right now. The leading bar
        /// blinks when true; otherwise the bar column reserves space
        /// but paints nothing. Resolved at adapter time from raw
        /// event timing against `state.nowTick`.
        let isInProgress: Bool
        let notebookLink: NotebookLink?
        /// True for the last row in a list so the row's bottom rule is
        /// suppressed. The section header below already supplies its own
        /// top rule; stacking both produced a visible "double divider."
        let hidesBottomRule: Bool

        // Layout (pre-resolved from DesignSystem)
        let columnGap: CGFloat
        let timeColumnWidth: CGFloat
        let titleSpacing: CGFloat
        let timeFontSize: CGFloat
        let titleFontSize: CGFloat
        let locationFontSize: CGFloat
        let durationFontSize: CGFloat
        /// SF Symbol point size for the passed-event checkmark badge.
        /// Slightly larger than the mono text size so the optical
        /// weight matches.
        let iconBadgeSize: CGFloat
        let verticalPadding: CGFloat
        /// Width of the leading in-progress bar column. Reserved
        /// regardless of state so layout doesn't shift when bars
        /// appear / disappear.
        let barWidth: CGFloat
        /// Gap between the leading bar column and the time text.
        let barTrailingGap: CGFloat

        // Colors (pre-resolved)
        let timeColor: Color
        let titleColor: Color
        let locationColor: Color
        let durationColor: Color
        let notebookLinkColor: Color
        let notebookLinkBorder: Color
        let ruleColor: Color
        let barColor: Color
    }

    /// Trailing badge content. Text covers Apple-formatted relative
    /// strings ("in 30 min" / "in 2 hr" — see `Date.RelativeFormatStyle`)
    /// and the "All day" override. Icon covers state markers — a SF
    /// Symbol with its own color, since active and passed states want
    /// different visual weights. Icon variants are intentionally
    /// localization-free; only the VoiceOver label is translated.
    enum Badge: Equatable {
        case text(String)
        case icon(systemName: String, color: Color, accessibilityLabel: String)
    }
}

// MARK: - Model init

extension BriefEventRow.Model {
    init(
        id: String,
        time: String,
        title: String,
        location: String?,
        duration: BriefEventRow.Badge,
        isInProgress: Bool,
        notebookLink: NotebookLink?,
        hidesBottomRule: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.location = location
        self.duration = duration
        self.isInProgress = isInProgress
        self.notebookLink = notebookLink
        self.hidesBottomRule = hidesBottomRule

        // Spec values from the React `Notebook Tabs - Dark Mode`
        // event row: 64pt time column, 14pt gap, 11pt vertical
        // padding, 11pt mono time, 16pt serif title, 10.5pt mono
        // duration.
        self.columnGap = 14
        self.timeColumnWidth = 64
        self.titleSpacing = 4
        self.timeFontSize = 11
        self.titleFontSize = 16
        self.locationFontSize = 11
        self.durationFontSize = 10.5
        self.iconBadgeSize = 12
        self.verticalPadding = 11
        self.barWidth = 3
        self.barTrailingGap = 10

        self.timeColor = ds.colors.ink2
        self.titleColor = ds.colors.ink
        self.locationColor = ds.colors.ink2
        self.durationColor = ds.colors.ink2
        self.notebookLinkColor = ds.colors.ink2
        self.notebookLinkBorder = ds.colors.rule
        self.ruleColor = ds.colors.rule
        // `inkPure` is the saturated black/white reserved for cases
        // where the warm-tinted `ink` token reads as too muted — a
        // 3pt vertical indicator against `paper` is exactly that case.
        self.barColor = ds.colors.inkPure
    }
}
