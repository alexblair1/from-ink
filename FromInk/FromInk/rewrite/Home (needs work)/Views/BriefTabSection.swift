import SwiftUI

/// The brief's tab-based content area — replaces both the old
/// `BriefCountsBar` (collapsed) and the old `highlightsSection`
/// (expanded). When `activeTab` is nil, only the tab strip renders
/// (collapsed). When non-nil, the tab strip + day header + the
/// tab-specific body all render.
///
/// Feature view — composes Component views, no TCA imports.
///
struct BriefTabSection: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BriefTabStrip(model: model.tabStrip)

            if model.activeTab != nil {
                expandedBody
                    // -3pt overlap: panel slides up under the active
                    // tab's bottom edge so the tab's "pressed" shadows
                    // bleed seamlessly into the panel surface. Pairs
                    // with the seam-killer paper strip drawn at the
                    // bottom of the active tab inside the tab strip.
                    .padding(.top, model.panelOverlap)
                    .background(model.panelBackground)
                    .transition(.opacity)
            }
        }
        // Honor the same horizontal inset that the masthead, lede, and
        // brief meta row use.
        .padding(.horizontal, model.horizontalPadding)
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(spacing: 0) {
            // No day header — the masthead above already shows the date.
            // Showing it twice was busy and redundant.
            switch model.activeTab {
            case .calendar?:
                calendarBody
            case .reminders?:
                remindersBody
            case .birthdays?:
                birthdaysBody
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var calendarBody: some View {
        if model.events.isEmpty {
            BriefEmptyMessage(text: model.emptyCalendarText)
        } else {
            ForEach(model.events) { event in
                BriefEventRow(model: event)
            }
        }
    }

    @ViewBuilder
    private var remindersBody: some View {
        if model.reminders.isEmpty {
            BriefEmptyMessage(text: model.emptyRemindersText)
        } else {
            ForEach(model.reminders) { reminder in
                BriefReminderRow(model: reminder)
            }
        }
    }

    @ViewBuilder
    private var birthdaysBody: some View {
        if model.birthdays.isEmpty {
            BriefEmptyMessage(text: model.emptyBirthdaysText)
        } else {
            ForEach(model.birthdays) { birthday in
                BriefBirthdayRow(model: birthday)
            }
        }
    }
}

// MARK: - Empty message

/// Small empty-state row shown when a tab has no items. Quiet single-line
/// message that matches the editorial chrome.
///
struct BriefEmptyMessage: View {
    let text: String
    private let ds = DesignSystem.standard

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(ds.colors.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ds.spacing.base)
    }
}

// MARK: - Model

extension BriefTabSection {
    struct Model {
        let activeTab: BriefTab?
        let tabStrip: BriefTabStrip.Model
        let events: [BriefEventRow.Model]
        let reminders: [BriefReminderRow.Model]
        let birthdays: [BriefBirthdayRow.Model]
        let emptyCalendarText: String
        let emptyRemindersText: String
        let emptyBirthdaysText: String
        let horizontalPadding: CGFloat
        let panelOverlap: CGFloat
        let panelBackground: Color
    }
}

// MARK: - Model init

extension BriefTabSection.Model {
    init(
        activeTab: BriefTab?,
        tabStrip: BriefTabStrip.Model,
        events: [BriefEventRow.Model],
        reminders: [BriefReminderRow.Model],
        birthdays: [BriefBirthdayRow.Model],
        ds: DesignSystem = .standard
    ) {
        self.activeTab = activeTab
        self.tabStrip = tabStrip
        self.events = events
        self.reminders = reminders
        self.birthdays = birthdays
        self.emptyCalendarText = AppStrings.Home.emptyCalendar
        self.emptyRemindersText = AppStrings.Home.emptyReminders
        self.emptyBirthdaysText = AppStrings.Home.emptyBirthdays
        self.horizontalPadding = ds.spacing.lg
        // Derived from the same NeumorphicTabStyle token the tab strip
        // uses for its seam offset — guaranteed to stay in sync. Tuning
        // seamOffset in NeumorphicTokens automatically retunes both.
        self.panelOverlap = ds.neumorphicTab.panelOverlap
        self.panelBackground = ds.colors.paper
    }
}
