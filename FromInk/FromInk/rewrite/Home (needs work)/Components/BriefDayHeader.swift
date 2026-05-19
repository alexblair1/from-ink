import SwiftUI

/// Day header shown at the top of the expanded brief body: weekday + month/day
/// + optional "Today" pill on the left, count summary on the right.
///
/// Lives inside the brief expansion, not the masthead. The masthead has its
/// own (much larger) date block; this is the smaller "you're looking at this
/// day" reference inside the tab body.
///
/// Stateless component.
///
struct BriefDayHeader: View {
    let model: Model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: model.daySpacing) {
            (
                Text(model.weekday)
                    .foregroundStyle(model.weekdayColor)
                +
                Text(" ")
                +
                Text(model.monthDay)
                    .italic()
                    .foregroundStyle(model.monthDayColor)
            )
            .font(model.dayFont)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let todayLabel = model.todayPillLabel {
                Text(todayLabel)
                    .font(.system(size: model.pillFontSize, weight: .medium, design: .monospaced))
                    .tracking(model.pillTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(model.pillForeground)
                    .padding(.horizontal, model.pillHorizontalPadding)
                    .padding(.vertical, model.pillVerticalPadding)
                    .background(model.pillBackground)
            }

            Spacer(minLength: 0)

            Text(model.countSummary)
                .font(.system(size: model.countFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(model.countColor)
                .lineLimit(1)
        }
        .padding(.vertical, model.verticalPadding)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(model.ruleColor)
                .frame(height: 1)
        }
    }
}

// MARK: - Model

extension BriefDayHeader {
    struct Model {
        let weekday: String
        let monthDay: String
        let todayPillLabel: String?
        let countSummary: String

        let dayFont: Font
        let weekdayColor: Color
        let monthDayColor: Color
        let pillForeground: Color
        let pillBackground: Color
        let pillFontSize: CGFloat
        let pillTracking: CGFloat
        let pillHorizontalPadding: CGFloat
        let pillVerticalPadding: CGFloat
        let countFontSize: CGFloat
        let countColor: Color
        let daySpacing: CGFloat
        let verticalPadding: CGFloat
        let ruleColor: Color
    }
}

// MARK: - Model init

extension BriefDayHeader.Model {
    init(
        weekday: String,
        monthDay: String,
        isToday: Bool,
        todayLabel: String,
        countSummary: String,
        ds: DesignSystem = .standard
    ) {
        self.weekday = weekday
        self.monthDay = monthDay
        self.todayPillLabel = isToday ? todayLabel : nil
        self.countSummary = countSummary

        self.dayFont = .system(size: 22, weight: .regular, design: .serif)
        self.weekdayColor = ds.colors.ink
        self.monthDayColor = ds.colors.ink2
        self.pillForeground = ds.colors.paperOnInk
        self.pillBackground = ds.colors.ink
        self.pillFontSize = 9.5
        self.pillTracking = 1.4
        self.pillHorizontalPadding = 7
        self.pillVerticalPadding = 4
        self.countFontSize = 11
        self.countColor = ds.colors.ink2
        self.daySpacing = 10
        self.verticalPadding = ds.spacing.sm
        self.ruleColor = ds.colors.rule
    }
}
