import SwiftUI

/// Thin domain adapter over `NeumorphicTabStrip` — maps brief data
/// (event/reminder/birthday counts + active tab) into the generic tab
/// component's `Tab` value type.
///
/// All visual treatment (raised/pressed shadows, seam-killer paper strip,
/// row layout, accessibility) lives in `NeumorphicTabStrip`. This file
/// only knows about `BriefTab`, the three SF Symbol mappings, and the
/// localized labels.
///
struct BriefTabStrip: View {
    let model: Model

    var body: some View {
        NeumorphicTabStrip<BriefTab>(
            tabs: model.tabs,
            showsLabel: model.showsLabel,
            onTabTapped: model.onTabTapped
        )
    }
}

// MARK: - Model

extension BriefTabStrip {
    struct Model {
        let tabs: [NeumorphicTabStrip<BriefTab>.Tab]
        let showsLabel: Bool
        let onTabTapped: (BriefTab) -> Void
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
            .init(
                id: .calendar,
                iconName: "calendar.day.timeline.left",
                label: AppStrings.Home.tabCalendar,
                countText: "\(eventCount)",
                isActive: activeTab == .calendar,
                isCountZero: eventCount == 0
            ),
            .init(
                id: .reminders,
                iconName: "checkmark.circle.dotted",
                label: AppStrings.Home.tabReminders,
                countText: "\(reminderCount)",
                isActive: activeTab == .reminders,
                isCountZero: reminderCount == 0
            ),
            .init(
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
    }
}
