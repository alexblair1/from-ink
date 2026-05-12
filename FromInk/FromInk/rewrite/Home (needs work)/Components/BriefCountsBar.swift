import SwiftUI

/// Counts row: icon + serif numeral + mono label, chevron with 44pt hit target.
/// Tappable — toggles the daily brief expanded state.
/// Component view — no TCA imports.
///
struct BriefCountsBar: View {
    let model: Model

    var body: some View {
        Button(action: model.onToggle) {
            HStack {
                HStack(spacing: model.countsSpacing) {
                    countItem(
                        icon: "calendar",
                        number: model.eventCount,
                        label: model.eventsLabel
                    )
                    countItem(
                        icon: "line.3.horizontal.decrease",
                        number: model.reminderCount,
                        label: model.remindersLabel
                    )
                }

                Spacer()

                Image(systemName: model.chevronIcon)
                    .font(.system(size: model.chevronSize, weight: .medium))
                    .foregroundStyle(model.chevronColor)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
            .frame(minHeight: model.chevronHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func countItem(
        icon: String,
        number: String,
        label: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: model.countInnerSpacing) {
            Image(systemName: icon)
                .font(model.iconFont)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.iconColor)

            Text(number)
                .font(model.numberFont)
                .foregroundStyle(model.numberColor)

            MonoLabel(label, color: model.labelColor)
        }
    }
}

// MARK: - Model

extension BriefCountsBar {
    struct Model {
        let eventCount: String
        let eventsLabel: String
        let reminderCount: String
        let remindersLabel: String
        let onToggle: () -> Void
        let chevronIcon: String
        let iconFont: Font
        let iconColor: Color
        let numberFont: Font
        let numberColor: Color
        let labelColor: Color
        let countsSpacing: CGFloat
        let countInnerSpacing: CGFloat
        let chevronColor: Color
        let chevronSize: CGFloat
        let chevronHitTarget: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
    }
}

// MARK: - Model init

extension BriefCountsBar.Model {
    init(
        eventCount: Int,
        reminderCount: Int,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.eventCount = "\(eventCount)"
        self.eventsLabel = AppStrings.Home.events
        self.reminderCount = "\(reminderCount)"
        self.remindersLabel = AppStrings.Home.due
        self.onToggle = onToggle
        self.chevronIcon = isExpanded ? "chevron.up" : "chevron.down"
        self.iconFont = ds.typography.footnote
        self.iconColor = ds.colors.ink2
        self.numberFont = ds.typography.numerals(size: 24)
        self.numberColor = ds.colors.ink
        self.labelColor = ds.colors.ink2
        self.countsSpacing = ds.spacing.lg
        self.countInnerSpacing = ds.spacing.xs
        self.chevronColor = ds.colors.ink
        self.chevronSize = 14
        self.chevronHitTarget = ds.layout.hitTarget
        self.horizontalPadding = ds.spacing.lg
        self.verticalPadding = ds.spacing.base
    }
}
