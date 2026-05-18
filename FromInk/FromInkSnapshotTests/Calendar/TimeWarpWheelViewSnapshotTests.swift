import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for the stateless Time Warp wheel layout.
///
/// Each test pins a wheel viewport size matching real device widths (so the
/// edge-fade mask + center-pointer composition lands in roughly the same pixel
/// positions as production). Locale stress tests confirm the same wheel
/// chassis works with non-Latin scripts and RTL-friendly digit systems.
///
/// Wheel content is generated from a fixed Wednesday May 13 2026 anchor; the
/// strip covers ±20 days around that anchor. Tests vary `selectedDate` to
/// place different cell varieties (today, weekend, week-start) at the
/// wheel's geometric center.
///
final class TimeWarpWheelViewSnapshotTests: XCTestCase {

    // MARK: - Reference dates

    /// 2026-05-13 12:00 UTC = Wednesday (verified).
    private static let referenceToday = Date(timeIntervalSince1970: 1_778_673_600)

    private static let iPadViewport: (CGFloat, CGFloat) = (820, 120)
    private static let iPhoneViewport: (CGFloat, CGFloat) = (393, 96)

    // MARK: - iPad

    func test_iPad_today_centered() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                selectedDate: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_pastSunday_centered() {
        // Selected = Sunday 5/10 — US week-start cell at center; today (Wed)
        // sits 3 cells right with italic + "today" mini-label.
        let sunday = Self.referenceToday.addingTimeInterval(-3 * 86_400)
        assertSnapshot(
            of: makeView(
                device: .iPad,
                selectedDate: sunday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_futureFriday_centered() {
        // Selected = Friday 5/22 — distant future weekday at center; today
        // sits 9 cells left and falls off into the edge fade.
        let friday = Self.referenceToday.addingTimeInterval(9 * 86_400)
        assertSnapshot(
            of: makeView(
                device: .iPad,
                selectedDate: friday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - iPhone

    func test_iPhone_today_centered() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                selectedDate: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPhone_pastWeekday_centered() {
        let tuesday = Self.referenceToday.addingTimeInterval(-1 * 86_400)
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                selectedDate: tuesday,
                today: Self.referenceToday,
                calendar: .gregorianUS,
                locale: .enUS
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Locale stress

    func test_iPad_arSA_today_centered() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                selectedDate: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianSA,
                locale: .arSA
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_iPad_jaJP_today_centered() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                selectedDate: Self.referenceToday,
                today: Self.referenceToday,
                calendar: .gregorianJP,
                locale: .jaJP
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Helper

    private func makeView(
        device: TimeWarpWheelView.Model.Device,
        selectedDate: Date,
        today: Date,
        calendar: Foundation.Calendar,
        locale: Locale
    ) -> some View {
        let viewport: (CGFloat, CGFloat) = {
            switch device {
            case .iPad:   return Self.iPadViewport
            case .iPhone: return Self.iPhoneViewport
            }
        }()

        let dates = makeDates(around: today, range: 20, calendar: calendar)
        let model = TimeWarpWheelView.Model(
            device: device,
            dates: dates,
            selectedDate: selectedDate,
            today: today,
            calendar: calendar,
            locale: locale
        )

        return TimeWarpWheelView(model: model)
            .frame(width: viewport.0, height: viewport.1)
            .background(Color("ink/Paper"))
            .environment(\.locale, locale)
            .colorScheme(.light)
    }

    /// Generate ±range days around `anchor`, DST-safe via Calendar arithmetic.
    private func makeDates(
        around anchor: Date,
        range: Int,
        calendar: Foundation.Calendar
    ) -> [Date] {
        (-range...range).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: anchor)
        }
    }
}

// MARK: - Fixture helpers (duplicated to keep snapshot test files self-contained)

private extension Foundation.Calendar {
    static let gregorianUS: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        cal.locale = .enUS
        return cal
    }()

    static let gregorianSA: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        cal.locale = .arSA
        return cal
    }()

    static let gregorianJP: Foundation.Calendar = {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        cal.locale = .jaJP
        return cal
    }()
}

private extension Locale {
    static let enUS = Locale(identifier: "en_US")
    static let arSA = Locale(identifier: "ar_SA@numbers=arab")
    static let jaJP = Locale(identifier: "ja_JP")
}
