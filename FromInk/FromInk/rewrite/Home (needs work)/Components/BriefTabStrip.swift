import SwiftUI

/// Home-screen brief tab strip — Calendar / Reminders / Birthdays.
///
/// Thin specialization of the generic `InkTabStrip<ID>` primitive. The
/// visual treatment lives in `InkTabStrip` so the Dispatch modal can
/// reuse the same component for its destination selector (per the
/// "Notebook — Reimagined" design's call to share the home-tabs UI).
struct BriefTabStrip: View {
    let model: Model

    var body: some View {
        InkTabStrip<BriefTab>(model: model.inner)
    }
}

// MARK: - Model

extension BriefTabStrip {
    struct Model {
        let inner: InkTabStrip<BriefTab>.Model

        init(
            activeTab: BriefTab?,
            eventCount: Int,
            reminderCount: Int,
            birthdayCount: Int,
            showsLabel: Bool = true,
            onTabTapped: @escaping (BriefTab) -> Void
        ) {
            let tabs: [InkTabStrip<BriefTab>.Tab] = [
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
            self.inner = .standard(tabs: tabs, showsLabel: showsLabel, onTabTapped: onTabTapped)
        }
    }
}
