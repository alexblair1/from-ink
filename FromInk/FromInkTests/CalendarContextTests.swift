import XCTest
@testable import FromInk

final class CalendarContextTests: XCTestCase {

    // MARK: - dayKey locale independence (dates_edd §12.2)

    func test_dayKey_isCalendarIndependent() {
        let utcNoon = Date(timeIntervalSince1970: 1_778_673_600) // 2026-05-13 12:00 UTC

        let contexts: [(String, CalendarContext)] = [
            ("en_US Gregorian", .fixed(
                now: utcNoon,
                timeZone: TimeZone(identifier: "UTC")!,
                calendar: Calendar(identifier: .gregorian),
                locale: Locale(identifier: "en_US")
            )),
            ("th_TH Buddhist", .fixed(
                now: utcNoon,
                timeZone: TimeZone(identifier: "UTC")!,
                calendar: Calendar(identifier: .buddhist),
                locale: Locale(identifier: "th_TH")
            )),
            ("ja_JP Japanese", .fixed(
                now: utcNoon,
                timeZone: TimeZone(identifier: "UTC")!,
                calendar: Calendar(identifier: .japanese),
                locale: Locale(identifier: "ja_JP")
            ))
        ]

        for (label, cal) in contexts {
            XCTAssertEqual(
                cal.dayKey(utcNoon), "2026-05-13",
                "dayKey must be Gregorian regardless of user calendar — \(label)"
            )
        }
    }

    // MARK: - dayKey timezone sensitivity (dates_edd §12.3)

    func test_dayKey_reflectsUserTimezone() {
        let moment = Date(timeIntervalSince1970: 1_778_708_700) // 2026-05-13 21:45 UTC

        let nyc = CalendarContext.fixed(
            now: moment, timeZone: TimeZone(identifier: "America/New_York")!
        )
        let tokyo = CalendarContext.fixed(
            now: moment, timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )

        XCTAssertEqual(nyc.dayKey(moment), "2026-05-13")  // 5:45 PM local
        XCTAssertEqual(tokyo.dayKey(moment), "2026-05-14") // 6:45 AM local next day
    }

    // MARK: - DST (dates_edd §12.4)

    func test_add_handlesSpringForward() {
        // 2026-03-08 06:30 UTC = 01:30 EST (before spring forward in America/New_York)
        let beforeDST = Date(timeIntervalSince1970: 1_772_951_400)
        let cal = CalendarContext.fixed(
            now: beforeDST,
            timeZone: TimeZone(identifier: "America/New_York")!
        )

        let oneDayLater = cal.add(.day, 1, beforeDST)

        // "1 day later" = same local time (01:30 EDT) = 23 wall-clock hours
        let elapsed = oneDayLater.timeIntervalSince(beforeDST)
        XCTAssertEqual(elapsed, 23 * 3600, accuracy: 1)
    }

    // MARK: - isSameDay

    func test_isSameDay_sameLocalDay() {
        let morning = Date(timeIntervalSince1970: 1_778_630_400)  // 2026-05-13 00:00 UTC
        let evening = Date(timeIntervalSince1970: 1_778_687_160)  // 2026-05-13 15:46 UTC

        let cal = CalendarContext.fixed(
            now: morning,
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertTrue(cal.isSameDay(morning, evening))
    }

    func test_isSameDay_differentLocalDays() {
        let may14 = Date(timeIntervalSince1970: 1_778_716_800)  // 2026-05-14 00:00 UTC
        let may13 = Date(timeIntervalSince1970: 1_778_630_400)  // 2026-05-13 00:00 UTC

        let cal = CalendarContext.fixed(
            now: may13,
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertFalse(cal.isSameDay(may13, may14))
    }

    // MARK: - isToday

    func test_isToday_usesFixedNow() {
        let fixedNow = Date(timeIntervalSince1970: 1_778_673_600) // 2026-05-13 12:00 UTC
        let cal = CalendarContext.fixed(
            now: fixedNow,
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertTrue(cal.isToday(fixedNow))

        let tomorrow = cal.add(.day, 1, fixedNow)
        XCTAssertFalse(cal.isToday(tomorrow))
    }

    // MARK: - parseISO8601Date

    func test_parseISO8601Date_validDate() {
        let cal = CalendarContext.fixed(
            now: Date(),
            timeZone: TimeZone(identifier: "UTC")!
        )

        let parsed = cal.parseISO8601Date("2026-05-13")
        XCTAssertNotNil(parsed)

        let dayKey = cal.dayKey(parsed!)
        XCTAssertEqual(dayKey, "2026-05-13")
    }

    func test_parseISO8601Date_invalidString_returnsNil() {
        let cal = CalendarContext.fixed(
            now: Date(),
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertNil(cal.parseISO8601Date("May 13, 2026"))
        XCTAssertNil(cal.parseISO8601Date("Friday"))
        XCTAssertNil(cal.parseISO8601Date(""))
    }

    // MARK: - dayKey format

    func test_dayKey_format() {
        let cal = CalendarContext.fixed(
            now: Date(timeIntervalSince1970: 1_778_673_600), // 2026-05-13 12:00 UTC
            timeZone: TimeZone(identifier: "UTC")!
        )

        let key = cal.dayKey(cal.now())
        XCTAssertEqual(key.count, 10)
        XCTAssertEqual(key.filter { $0 == "-" }.count, 2)
        XCTAssertEqual(key, "2026-05-13")
    }
}
