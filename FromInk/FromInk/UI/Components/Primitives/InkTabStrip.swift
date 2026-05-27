import SwiftUI

/// Generic ink-on-paper tab strip — the flat segmented control that
/// appears on the home screen (Calendar / Reminders / Birthdays) and
/// in the Dispatch modal (Calendar / Reminders / Mail).
///
/// One outer 1pt ink border surrounds N cells joined internally by 1pt
/// rule dividers. The active cell inverts to ink fill + paper text.
/// No shadows, no gradients — pure e-ink.
///
/// `ID` is the caller's identifier type for the active selection
/// (typically an enum). `BriefTabStrip` is a thin wrapper that
/// specializes this for `BriefTab`; new uses should consume this
/// primitive directly with their own ID type.
struct InkTabStrip<ID: Hashable>: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                cell(for: tab)
                if index < model.tabs.count - 1 {
                    // Internal divider between cells. Hidden when the
                    // adjacent cell on either side is active — the
                    // active cell's ink fill makes the divider redundant.
                    let leftActive = tab.isActive
                    let rightActive = model.tabs[index + 1].isActive
                    Rectangle()
                        .fill(leftActive || rightActive ? ds.colors.ink : ds.colors.rule)
                        .frame(width: model.dividerWidth)
                }
            }
        }
        .background(ds.colors.paper)
        .overlay(
            Rectangle().strokeBorder(ds.colors.ink, lineWidth: model.borderWidth)
        )
    }

    @ViewBuilder
    private func cell(for tab: Tab) -> some View {
        Button(action: { model.onTabTapped(tab.id) }) {
            HStack(spacing: model.contentGap) {
                Image(systemName: tab.iconName)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .foregroundStyle(tab.isActive ? ds.colors.paperOnInk : ds.colors.ink)

                if model.showsLabel {
                    Text(tab.label)
                        .font(.system(size: model.labelFontSize, weight: .medium, design: .monospaced))
                        .tracking(model.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(tab.isActive ? ds.colors.paperOnInk : ds.colors.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if let countText = tab.countText {
                    Text(countText)
                        .font(.system(size: model.countFontSize, weight: .light, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(countColor(for: tab))
                }
            }
            .padding(.horizontal, model.cellPaddingHorizontal)
            .frame(maxWidth: .infinity)
            .frame(height: model.cellHeight)
            .background(tab.isActive ? ds.colors.ink : ds.colors.paper)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(tab.isActive ? [.isButton, .isSelected] : [.isButton])
    }

    /// Active/inactive × zero/nonzero gives four legal count colors.
    /// Callers without counts get nil here (no-op).
    private func countColor(for tab: Tab) -> Color {
        switch (tab.isActive, tab.isCountZero) {
        case (true, true):   ds.colors.paperOnInk.opacity(0.55)
        case (true, false):  ds.colors.paperOnInk
        case (false, true):  ds.colors.ink3
        case (false, false): ds.colors.ink
        }
    }
}

// MARK: - Tab

extension InkTabStrip {
    struct Tab: Identifiable, Equatable {
        let id: ID
        let iconName: String
        let label: String
        /// Optional trailing count. Nil = don't render. Used by Home's
        /// brief tabs (always shown); Dispatch destinations omit it.
        let countText: String?
        let isActive: Bool
        let isCountZero: Bool

        init(
            id: ID,
            iconName: String,
            label: String,
            countText: String? = nil,
            isActive: Bool,
            isCountZero: Bool = false
        ) {
            self.id = id
            self.iconName = iconName
            self.label = label
            self.countText = countText
            self.isActive = isActive
            self.isCountZero = isCountZero
        }
    }
}

// MARK: - Model

extension InkTabStrip {
    struct Model {
        let tabs: [Tab]
        let showsLabel: Bool
        let onTabTapped: (ID) -> Void

        // Resolved geometry
        let cellHeight: CGFloat
        let cellPaddingHorizontal: CGFloat
        let contentGap: CGFloat
        let iconSize: CGFloat
        let labelFontSize: CGFloat
        let labelTracking: CGFloat
        let countFontSize: CGFloat
        let dividerWidth: CGFloat
        let borderWidth: CGFloat

        /// Standard geometry — verbatim from the Brief Tabs handoff
        /// spec, with a small bump in cell height to clear Apple's 44pt
        /// touch guideline on iOS (the web mock uses 36; touch needs 44).
        public static func standard(
            tabs: [Tab],
            showsLabel: Bool = true,
            onTabTapped: @escaping (ID) -> Void
        ) -> Model {
            Model(
                tabs: tabs,
                showsLabel: showsLabel,
                onTabTapped: onTabTapped,
                cellHeight: 44,
                cellPaddingHorizontal: showsLabel ? 14 : 12,
                contentGap: 8,
                iconSize: 14,
                labelFontSize: 10.5,
                labelTracking: 2.3,
                countFontSize: 15,
                dividerWidth: 1,
                borderWidth: 1
            )
        }
    }
}
