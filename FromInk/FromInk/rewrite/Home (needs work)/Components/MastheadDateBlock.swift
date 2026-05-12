import SwiftUI

/// Large serif date with collapse/expand toggle and event counts.
/// "Tuesday," in NY 56, "May 12." italic at 40.
/// Component view — no TCA imports.
///
struct MastheadDateBlock: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: model.innerSpacing) {
            // Date + collapse toggle
            HStack(alignment: .firstTextBaseline) {
                dateText
                Spacer()
                Button(action: model.onToggle) {
                    HStack(spacing: model.toggleSpacing) {
                        Text(model.toggleLabel)
                            .underline(color: model.toggleColor)
                        Image(systemName: model.toggleIcon)
                            .font(.system(size: model.toggleIconSize, weight: .medium))
                    }
                    .font(model.toggleFont)
                    .tracking(model.toggleTracking)
                    .foregroundStyle(model.toggleColor)
                }
                .buttonStyle(.plain)
            }

            // Counts row
            HStack(spacing: model.countsSpacing) {
                Spacer()
                HStack(spacing: model.countInnerSpacing) {
                    Image(systemName: "calendar")
                        .font(model.countIconFont)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.countColor)
                    MonoLabel(model.eventsLabel, color: model.countColor)
                }
                HStack(spacing: model.countInnerSpacing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(model.countIconFont)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.countColor)
                    MonoLabel(model.remindersLabel, color: model.countColor)
                }
            }
        }
        .padding(.horizontal, model.horizontalPadding)
    }

    private var dateText: some View {
        (
            Text(model.weekday)
                .foregroundStyle(model.weekdayColor)
            +
            Text(",")
                .foregroundStyle(model.commaColor)
        )
        .font(model.weekdayFont)
        .tracking(model.weekdayTracking)
        +
        Text(" ")
        +
        Text("\(model.monthDay).")
            .font(model.monthDayFont)
            .italic()
            .foregroundStyle(model.monthDayColor)
    }
}

// MARK: - Model

extension MastheadDateBlock {
    struct Model {
        let weekday: String
        let monthDay: String
        let isExpanded: Bool
        let onToggle: () -> Void
        let eventsLabel: String
        let remindersLabel: String
        let weekdayFont: Font
        let weekdayColor: Color
        let weekdayTracking: CGFloat
        let commaColor: Color
        let monthDayFont: Font
        let monthDayColor: Color
        let toggleLabel: String
        let toggleIcon: String
        let toggleFont: Font
        let toggleColor: Color
        let toggleTracking: CGFloat
        let toggleIconSize: CGFloat
        let toggleSpacing: CGFloat
        let countColor: Color
        let countIconFont: Font
        let countsSpacing: CGFloat
        let countInnerSpacing: CGFloat
        let horizontalPadding: CGFloat
        let innerSpacing: CGFloat
    }
}

// MARK: - Model init

extension MastheadDateBlock.Model {
    init(
        weekday: String,
        monthDay: String,
        eventCount: Int,
        reminderCount: Int,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.weekday = weekday
        self.monthDay = monthDay
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.eventsLabel = "\(eventCount) \(AppStrings.Home.events)"
        self.remindersLabel = "\(reminderCount) \(AppStrings.Home.due)"
        self.weekdayFont = .system(size: 56, weight: .regular, design: .serif)
        self.weekdayColor = ds.colors.ink
        self.weekdayTracking = -1.12
        self.commaColor = ds.colors.ink2
        self.monthDayFont = .system(size: 40, weight: .regular, design: .serif)
        self.monthDayColor = ds.colors.ink2
        self.toggleLabel = isExpanded
            ? AppStrings.Home.collapse.uppercased()
            : AppStrings.Home.readMore.uppercased()
        self.toggleIcon = isExpanded ? "chevron.up" : "chevron.down"
        self.toggleFont = ds.typography.monoLabel
        self.toggleColor = ds.colors.ink
        self.toggleTracking = 11 * 0.18
        self.toggleIconSize = 10
        self.toggleSpacing = 6
        self.countColor = ds.colors.ink
        self.countIconFont = ds.typography.footnote
        self.countsSpacing = ds.spacing.lg
        self.countInnerSpacing = ds.spacing.xs
        self.horizontalPadding = ds.spacing.lg
        self.innerSpacing = ds.spacing.sm
    }
}
