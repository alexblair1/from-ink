import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for the Time Warp wheel's `DayCellView`.
///
/// All fixtures are constructed from real `Date` + `Calendar` + `Locale`
/// values — the same boundary the production wiring view crosses. Locale
/// stress cases lock in correct localization of:
///
/// - The day-of-week letter (Latin / CJK / Arabic / Hebrew / Devanagari)
/// - The day number's numbering system (Latin / Arabic-Indic / Devanagari / Thai)
/// - Week-start (`Calendar.firstWeekday` — Sunday in US, Saturday in SA, Monday in GB)
/// - Weekend definition (`Calendar.isDateInWeekend` — Sat+Sun Gregorian, Fri+Sat ar_SA)
///
/// All anchored to 2026-05-13 12:00 UTC (a Wednesday in NY local time).
///
final class DayCellViewSnapshotTests: XCTestCase {

    // MARK: - Reference dates
    //
    // All epoch values verified against the Gregorian calendar — Wednesday is
    // intentionally chosen as "today" so the cell renders the middle of the
    // typographic hierarchy (not a week-start, not a weekend).

    /// 2026-05-13 12:00 UTC = 2026-05-13 08:00 EDT (Wednesday).
    private static let referenceToday = Date(timeIntervalSince1970: 1_778_673_600)

    /// 2026-05-14 12:00 UTC — Thursday.
    private static let oneDayLater = referenceToday.addingTimeInterval(86_400)

    /// 2026-05-10 12:00 UTC — Sunday (US Gregorian week start).
    private static let threeDaysEarlier = referenceToday.addingTimeInterval(-3 * 86_400)

    /// 2026-05-09 12:00 UTC — Saturday (US Gregorian weekend).
    private static let fourDaysEarlier = referenceToday.addingTimeInterval(-4 * 86_400)

    /// 2026-05-11 12:00 UTC — Monday (GB/EU Gregorian week start).
    private static let twoDaysEarlier = referenceToday.addingTimeInterval(-2 * 86_400)

    /// 2026-05-22 12:00 UTC — Friday (far-away weekday).
    private static let nineDaysLater = referenceToday.addingTimeInterval(9 * 86_400)

    /// 2026-06-12 12:00 UTC — Friday (max-distance weekday).
    private static let thirtyDaysLater = referenceToday.addingTimeInterval(30 * 86_400)

    /// 2026-05-15 12:00 UTC — Friday (ar_SA weekend per Calendar.isDateInWeekend).
    private static let friday = Date(timeIntervalSince1970: 1_778_846_400)

    // MARK: - iPad states (en_US Gregorian)

    func test_iPad_today_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: true,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_today_unselected_showsItalicAndTodayLabel() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_weekday_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.oneDayLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: true,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_weekday_unselected() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.oneDayLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_weekStart_unselected_tallerTick() {
        // Sunday 5/10 in en_US Gregorian — firstWeekday = 1 (Sunday).
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.threeDaysEarlier,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 3
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_weekend_unselected_shortTickAndDimLetter() {
        // Saturday 5/9 in en_US Gregorian — Sat+Sun is weekend.
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.fourDaysEarlier,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 4
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_unselected_farAway_fadedOpacity() {
        // distance 9 → opacity = max(0.22, 1 - 9*0.045) = 0.595. Date is Friday
        // 5/22 — a weekday in en_US, so the cell isn't confounded by weekend styling.
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.nineDaysLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 9
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_unselected_maxDistance_clampedOpacity() {
        // distance 30 → opacity clamped to 0.22
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.thirtyDaysLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 30
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - iPad locale stress

    /// Week-start in en_GB is Monday (firstWeekday = 2) — Monday gets the taller tick,
    /// not Sunday. Same date and tokens as the en_US weekday test, different calendar.
    func test_iPad_enGB_monday_isWeekStart() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.twoDaysEarlier,           // Mon 5/11
                today: Self.referenceToday,
                calendar: .gregorianGB,
                locale: .enGB,
                isSelected: false,
                distance: 2
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Japanese narrow weekday symbols are CJK ideographs ("水" for Wednesday).
    /// Latin digit system (Japan uses Arabic numerals); Gregorian calendar.
    func test_iPad_jaJP_today_kanjiWeekday() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianJP,
                locale: .jaJP,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Arabic locale: weekday letter in Arabic script ("ر" for Wednesday "الأربعاء"),
    /// Arabic-Indic digits ("١٣" for 13), and Fri+Sat is the weekend.
    func test_iPad_arSA_today_arabicLetterAndDigit() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianSA,
                locale: .arSA,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Arabic locale + Friday: `isDateInWeekend` is true (Fri+Sat in ar_SA).
    func test_iPad_arSA_friday_isWeekend() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.friday,
                today: Self.referenceToday,
                calendar: .gregorianSA,
                locale: .arSA,
                isSelected: false,
                distance: 2
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Hebrew locale: weekday letter in Hebrew script. Sunday is week-start in he_IL.
    func test_iPad_heIL_sunday_isWeekStart() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.threeDaysEarlier,         // Sun 5/10
                today: Self.referenceToday,
                calendar: .gregorianIL,
                locale: .heIL,
                isSelected: false,
                distance: 3
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Hindi locale: weekday letter in Devanagari; day number in Devanagari digits ("१३").
    func test_iPad_hiIN_today_devanagariDigit() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianIN,
                locale: .hiIN,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Thai locale + Buddhist calendar: day number in Thai digits ("๑๓"). Calendar
    /// is Buddhist but day-of-month is identical to Gregorian.
    func test_iPad_thTH_today_thaiDigitBuddhistCalendar() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .buddhistTH,
                locale: .thTH,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - iPhone states (en_US Gregorian)

    func test_iPhone_today_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: true,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPhone_today_unselected_showsItalic() {
        // iPhone variant has no TODAY label and no baseline marker, but
        // italic + tall tick still apply.
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                date: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPhone_weekday_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                date: Self.oneDayLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: true,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPhone_weekday_unselected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                date: Self.oneDayLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPhone_weekend_unselected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                date: Self.fourDaysEarlier,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 4
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPhone_unselected_maxDistance_clampedOpacity() {
        // distance 30 → opacity clamped to 0.22 (falloff factor 0.05 on iPhone)
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                date: Self.thirtyDaysLater,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS,
                isSelected: false,
                distance: 30
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Helper

    /// Builds a renderable DayCellView wrapped on the warm paper background the
    /// wheel sits on, with `colorScheme(.light)` pinned so the asset catalog
    /// resolves to the light variants deterministically. For RTL locales the
    /// surrounding container respects layoutDirection so any future LTR/RTL
    /// drift would surface in the snapshot — the cell itself is a VStack and
    /// is layout-direction invariant.
    private func makeView(
        device: DayCellView.Model.Device,
        date: Date,
        today: Date,
        calendar: Foundation.Calendar,
        locale: Locale,
        isSelected: Bool,
        distance: Int
    ) -> some View {
        let model = DayCellView.Model(
            device: device,
            date: date,
            today: today,
            calendar: calendar,
            locale: locale,
            isSelected: isSelected,
            distanceFromSelection: distance
        )
        return DayCellView(model: model)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(Color("ink/Paper"))
            .environment(\.locale, locale)
            .colorScheme(.light)
    }
}

// MARK: - Fixture helpers

private extension Foundation.Calendar {
    /// US Gregorian — firstWeekday = 1 (Sunday).
    static let gregorianUS: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        cal.locale = .enUS
        return cal
    }()

    /// GB Gregorian — firstWeekday = 2 (Monday).
    static let gregorianGB: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        cal.locale = .enGB
        return cal
    }()

    /// Japan Gregorian — firstWeekday = 1 (Sunday); CJK weekday symbols.
    static let gregorianJP: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        cal.locale = .jaJP
        return cal
    }()

    /// Saudi Gregorian — firstWeekday = 7 (Saturday); weekend = Fri+Sat.
    static let gregorianSA: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        cal.locale = .arSA
        return cal
    }()

    /// Israeli Gregorian — firstWeekday = 1 (Sunday); weekend = Fri+Sat.
    static let gregorianIL: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        cal.locale = .heIL
        return cal
    }()

    /// India Gregorian — Devanagari digit system via locale.
    static let gregorianIN: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        cal.locale = .hiIN
        return cal
    }()

    /// Thai Buddhist calendar — year offset by +543, Thai digit system.
    static let buddhistTH: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .buddhist)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        cal.locale = .thTH
        return cal
    }()
}

private extension Locale {
    static let enUS = Locale(identifier: "en_US")
    static let enGB = Locale(identifier: "en_GB")
    static let jaJP = Locale(identifier: "ja_JP")
    /// Arabic-Indic digits explicitly. iOS may default ar_SA to either Latin or
    /// Arabic-Indic depending on region settings; the @numbers extension locks
    /// the test to the script we care about.
    static let arSA = Locale(identifier: "ar_SA@numbers=arab")
    static let heIL = Locale(identifier: "he_IL")
    /// Devanagari digits explicitly — hi_IN defaults to Latin in iOS.
    static let hiIN = Locale(identifier: "hi_IN@numbers=deva")
    /// Thai digits explicitly — th_TH defaults to Latin in iOS.
    static let thTH = Locale(identifier: "th_TH@numbers=thai")
}
