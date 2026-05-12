import SwiftUI

/// Large serif date — "Tuesday," in NY 56, "May 12." italic at 40.
/// Date only — counts and toggle live in BriefCountsBar.
/// Component view — no TCA imports.
///
struct MastheadDateBlock: View {
    let model: Model

    var body: some View {
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
        let weekdayFont: Font
        let weekdayColor: Color
        let weekdayTracking: CGFloat
        let commaColor: Color
        let monthDayFont: Font
        let monthDayColor: Color
    }
}

// MARK: - Model init

extension MastheadDateBlock.Model {
    init(
        weekday: String,
        monthDay: String,
        ds: DesignSystem = .standard
    ) {
        self.weekday = weekday
        self.monthDay = monthDay
        self.weekdayFont = .system(size: 56, weight: .regular, design: .serif)
        self.weekdayColor = ds.colors.ink
        self.weekdayTracking = -1.12
        self.commaColor = ds.colors.ink2
        self.monthDayFont = .system(size: 40, weight: .regular, design: .serif)
        self.monthDayColor = ds.colors.ink2
    }
}
