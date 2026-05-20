import SwiftUI

/// Flat ink-on-paper tab strip — Calendar / Reminders / Birthdays.
///
/// One outer 1pt ink border surrounds three cells joined internally by
/// 1pt rule dividers. Each cell has an SF Symbol, an optional mono-caps
/// label (hidden on compact widths), and a serif numeral count
/// right-aligned. The active cell inverts to ink fill with paper text.
/// No shadows, no gradients, no neumorphic anything — pure e-ink.
///
/// Spec: `Brief Tabs — handoff` (notes-app/project). Tokens used:
/// `ds.colors.{ink, ink2, ink3, paper, surface, rule, paperOnInk}`.
///
struct BriefTabStrip: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                cell(for: tab)
                if index < model.tabs.count - 1 {
                    // Internal divider between cells. Hidden when the
                    // adjacent cell on either side is active — the active
                    // cell's ink fill makes the divider redundant and the
                    // spec drops it (`border-right-color: --ink` on the
                    // active cell in CSS).
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
            // Outer ink border. Drawn as an overlay so the internal
            // dividers don't double up against it.
            Rectangle()
                .strokeBorder(ds.colors.ink, lineWidth: model.borderWidth)
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
                }

                Spacer(minLength: 0)

                Text(tab.countText)
                    .font(.system(size: model.countFontSize, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(countColor(for: tab))
            }
            .padding(.horizontal, model.cellPaddingHorizontal)
            .frame(maxWidth: .infinity)
            .frame(height: model.cellHeight)
            .background(tab.isActive ? ds.colors.ink : ds.colors.paper)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityValue(tab.countText)
        .accessibilityAddTraits(tab.isActive ? [.isButton, .isSelected] : [.isButton])
    }

    /// Resolves the count color across all four state combinations:
    /// active+nonzero (paper), active+zero (paper @ 55%), inactive+nonzero
    /// (ink), inactive+zero (ink3). Matches the spec table.
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

extension BriefTabStrip {
    struct Tab: Identifiable, Equatable {
        let id: BriefTab
        let iconName: String
        let label: String
        let countText: String
        let isActive: Bool
        let isCountZero: Bool
    }
}

// MARK: - Model

extension BriefTabStrip {
    struct Model {
        let tabs: [Tab]
        let showsLabel: Bool
        let onTabTapped: (BriefTab) -> Void

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
    }
}

// MARK: - Model init

extension BriefTabStrip.Model {
    init(
        activeTab: BriefTab?,
        eventCount: Int,
        reminderCount: Int,
        birthdayCount: Int,
        showsLabel: Bool = true,
        onTabTapped: @escaping (BriefTab) -> Void
    ) {
        self.tabs = [
            BriefTabStrip.Tab(
                id: .calendar,
                iconName: "calendar.day.timeline.left",
                label: AppStrings.Home.tabCalendar,
                countText: "\(eventCount)",
                isActive: activeTab == .calendar,
                isCountZero: eventCount == 0
            ),
            BriefTabStrip.Tab(
                id: .reminders,
                iconName: "checkmark.circle.dotted",
                label: AppStrings.Home.tabReminders,
                countText: "\(reminderCount)",
                isActive: activeTab == .reminders,
                isCountZero: reminderCount == 0
            ),
            BriefTabStrip.Tab(
                id: .birthdays,
                iconName: "gift",
                label: AppStrings.Home.tabBirthdays,
                countText: "\(birthdayCount)",
                isActive: activeTab == .birthdays,
                isCountZero: birthdayCount == 0
            ),
        ]
        self.showsLabel = showsLabel
        self.onTabTapped = onTabTapped

        // Geometry — verbatim from the Brief Tabs handoff spec, with
        // a small bump in cell height to clear Apple's 44pt touch
        // guideline on iOS (the web mock uses 36; touch needs 44).
        self.cellHeight = 44
        self.cellPaddingHorizontal = showsLabel ? 14 : 12
        self.contentGap = 8
        self.iconSize = 14
        self.labelFontSize = 10.5
        self.labelTracking = 2.3   // ~0.22em on a 10.5pt font
        self.countFontSize = 15
        self.dividerWidth = 1
        self.borderWidth = 1
    }
}
