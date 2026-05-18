import Foundation

extension AppStrings {
    enum Calendar {
        static let todayLabel = NSLocalizedString(
            "calendar.today.label",
            value: "today",
            comment: "Mini-label shown under today's date in the Time Warp wheel when today is not selected."
        )

        /// VoiceOver hint spoken after a wheel cell's date label, instructing
        /// the user what double-tapping the cell will do.
        static let wheelCellHint = NSLocalizedString(
            "calendar.wheel.cell.hint",
            value: "Double tap to view this day's brief.",
            comment: "VoiceOver hint for unselected Time Warp wheel cells."
        )
    }
}
