import SwiftUI

/// Three-tab row that lives at the top of the brief header — Calendar,
/// Reminders, Birthdays. Each tab shows an icon, a mono-uppercase label,
/// and a serif numeral count.
///
/// The active tab sits on `Paper`; inactive tabs sit on `Surface` with
/// 0.7 opacity on their icon/label so the active one reads as raised.
/// Bottom border is full ink — the same line that runs through the rest
/// of the editorial chrome.
///
/// Stateless. Activation is a property of the model, not the view.
///
struct BriefTabStrip: View {
    let model: Model

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.tabs.enumerated()), id: \.offset) { index, tab in
                let isLast = index == model.tabs.count - 1
                let nextIsActive = !isLast && model.tabs[index + 1].isActive
                // Hide the right divider when either neighbor is the active
                // tab — the active tab's "raised" background already reads
                // as a separator. A divider on either side would compete
                // visually with the contrast boundary.
                let hidesTrailingDivider = isLast || tab.isActive || nextIsActive
                tabButton(tab: tab, hidesTrailingDivider: hidesTrailingDivider)
            }
        }
        // No strip-level bottom rule — the bottom edge is per-tab, hidden
        // on the active tab to give the "raised tab" silhouette.
    }

    private func tabButton(tab: Model.Tab, hidesTrailingDivider: Bool) -> some View {
        Button(action: { model.onTabTapped(tab.tab) }) {
            HStack(spacing: model.tabInnerSpacing) {
                Image(systemName: tab.iconName)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .foregroundStyle(tab.isActive ? model.activeIconColor : model.inactiveIconColor)

                if model.showsLabel {
                    Text(tab.label)
                        .font(.system(size: model.labelSize, weight: .medium, design: .monospaced))
                        .tracking(model.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(tab.isActive ? model.activeLabelColor : model.inactiveLabelColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(tab.countText)
                    .font(.system(size: model.countSize, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(tab.isActive ? model.activeCountColor : model.inactiveCountColor)
            }
            .padding(.horizontal, model.tabHorizontalPadding)
            .padding(.vertical, model.tabVerticalPadding)
            .frame(maxWidth: .infinity)
            .background(tab.isActive ? model.activeBackground : model.inactiveBackground)
            // Top + bottom rules — per-tab so the active tab can omit
            // both. The result is a "tab" silhouette: inactive tabs are
            // capped on both edges (continuous with the brief body above
            // and the body below), the active tab opens into negative
            // space on both edges and reads as raised in/out.
            .overlay(alignment: .top) {
                if !tab.isActive {
                    Rectangle()
                        .fill(model.ruleColor)
                        .frame(height: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if !tab.isActive {
                    Rectangle()
                        .fill(model.ruleColor)
                        .frame(height: 1)
                }
            }
            .overlay(alignment: .trailing) {
                if !hidesTrailingDivider {
                    Rectangle()
                        .fill(model.tabDividerColor)
                        .frame(width: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityValue(tab.countText)
    }
}

// MARK: - Model

extension BriefTabStrip {
    struct Model {
        struct Tab: Identifiable {
            var id: BriefTab { tab }
            let tab: BriefTab
            let label: String
            let iconName: String
            let countText: String
            let isActive: Bool
        }

        let tabs: [Tab]
        let onTabTapped: (BriefTab) -> Void
        /// When false, each tab renders icon + count only — the text label
        /// is hidden but kept as the VoiceOver accessibility label. Set
        /// from `horizontalSizeClass == .compact` in the wiring view.
        let showsLabel: Bool

        let activeBackground: Color
        let inactiveBackground: Color
        let activeIconColor: Color
        let inactiveIconColor: Color
        let activeLabelColor: Color
        let inactiveLabelColor: Color
        let activeCountColor: Color
        let inactiveCountColor: Color
        let tabDividerColor: Color
        /// Color of the per-tab top/bottom rules and inter-tab dividers.
        /// Inactive tabs draw both top and bottom rules; the active tab
        /// omits them to read as raised.
        let ruleColor: Color

        let iconSize: CGFloat
        let labelSize: CGFloat
        let labelTracking: CGFloat
        let countSize: CGFloat
        let tabInnerSpacing: CGFloat
        let tabHorizontalPadding: CGFloat
        let tabVerticalPadding: CGFloat
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
        onTabTapped: @escaping (BriefTab) -> Void,
        ds: DesignSystem = .standard
    ) {
        self.tabs = [
            .init(
                tab: .calendar,
                label: AppStrings.Home.tabCalendar,
                iconName: "calendar.day.timeline.left",
                countText: "\(eventCount)",
                isActive: activeTab == .calendar
            ),
            .init(
                tab: .reminders,
                label: AppStrings.Home.tabReminders,
                iconName: "checkmark.circle.dotted",
                countText: "\(reminderCount)",
                isActive: activeTab == .reminders
            ),
            .init(
                tab: .birthdays,
                label: AppStrings.Home.tabBirthdays,
                iconName: "gift",
                countText: "\(birthdayCount)",
                isActive: activeTab == .birthdays
            ),
        ]
        self.onTabTapped = onTabTapped
        self.showsLabel = showsLabel

        self.activeBackground = ds.colors.paper
        self.inactiveBackground = ds.colors.surface
        self.activeIconColor = ds.colors.ink
        self.inactiveIconColor = ds.colors.ink2
        self.activeLabelColor = ds.colors.ink
        self.inactiveLabelColor = ds.colors.ink2
        self.activeCountColor = ds.colors.ink
        self.inactiveCountColor = ds.colors.ink2
        self.tabDividerColor = ds.colors.rule
        self.ruleColor = ds.colors.rule

        self.iconSize = 14
        self.labelSize = 11
        self.labelTracking = 1.5
        self.countSize = 20
        // Spec values from the React design source (`--tab-pad-y: 14px,
        // --tab-pad-x: 22px, gap: 10px`). Earlier values used the design
        // system's `.sm` / `.base` tokens which were too tight, giving the
        // tab strip a cramped feel relative to the spec.
        self.tabInnerSpacing = 10
        self.tabHorizontalPadding = 22
        self.tabVerticalPadding = 14
    }
}
