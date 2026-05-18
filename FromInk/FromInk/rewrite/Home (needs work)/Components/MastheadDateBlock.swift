import SwiftUI

/// Large serif date — "Tuesday," in NY 56, "May 12." italic at 40.
/// Date only — counts and toggle live in BriefCountsBar.
/// Component view — no TCA imports.
///
struct MastheadDateBlock: View {
    let model: Model

    var body: some View {
        (
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
                .foregroundStyle(model.monthDayColor)
        )
        // Single-line + minimumScaleFactor protects against verbose
        // localized weekdays ("Mittwoch", "الأربعاء", "水曜日") and narrow
        // containers (iPhone, iPad split view). Falls back to wrapping
        // only if the text can't shrink to fit.
        .lineLimit(model.lineLimit)
        .minimumScaleFactor(model.minimumScaleFactor)
    }
}

// MARK: - Model

extension MastheadDateBlock {
    struct Model {
        let weekday: String
        let monthDay: String
        let weekdayFont: Font
        let weekdayColor: Color
        let weekdayTracking: CGFloat
        let commaColor: Color
        let monthDayFont: Font
        let monthDayColor: Color
        let lineLimit: Int
        let minimumScaleFactor: CGFloat
    }
}

// MARK: - Model init

extension MastheadDateBlock.Model {
    init(
        weekday: String,
        monthDay: String,
        compact: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.weekday = weekday
        self.monthDay = monthDay
        self.weekdayFont = compact
            ? ds.typography.mastheadWeekdayCompact
            : ds.typography.mastheadWeekday
        self.weekdayColor = ds.colors.ink
        self.weekdayTracking = ds.layout.mastheadTracking
        self.commaColor = ds.colors.ink2
        self.monthDayFont = compact
            ? ds.typography.mastheadMonthDayCompact
            : ds.typography.mastheadMonthDay
        self.monthDayColor = ds.colors.ink2
        // Compact width never wraps — shrinks instead. Regular width may
        // wrap for very long compositions but doesn't usually need to.
        self.lineLimit = compact ? 1 : 2
        self.minimumScaleFactor = compact ? 0.5 : 0.8
    }
}
