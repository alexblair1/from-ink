import ComposableArchitecture
import Foundation

/// Single source of truth for date/time/calendar/timezone in the app.
///
/// All "what time is it" and "what day is this" calls route through here.
/// No call site reads `Date()` directly. No call site allocates DateFormatter.
///
/// See Documentation/dates_edd.md for the full specification.
///
struct CalendarContext: Sendable {
    /// The absolute current moment. The only producer of "now" in the app.
    var now: @Sendable () -> Date

    /// The user's preferred calendar (Gregorian, Buddhist, Japanese, etc.).
    var userCalendar: @Sendable () -> Calendar

    /// The user's current timezone.
    var userTimeZone: @Sendable () -> TimeZone

    /// The user's preferred locale for display formatting.
    var userLocale: @Sendable () -> Locale

    /// Stable day-key for cache keys and predicates.
    /// Always "yyyy-MM-dd", Gregorian, POSIX, in the user's timezone.
    var dayKey: @Sendable (Date) -> String

    /// Start of the user's current local day (as an absolute Date).
    var startOfDay: @Sendable (Date) -> Date

    /// True if two Dates fall on the same user-local day.
    var isSameDay: @Sendable (Date, Date) -> Bool

    /// True if a Date falls on the user's current local day.
    var isToday: @Sendable (Date) -> Bool

    /// Add a calendar component to a Date — DST-safe.
    var add: @Sendable (Calendar.Component, Int, Date) -> Date

    /// Parse a machine-readable date string (ISO-8601 "yyyy-MM-dd").
    /// Returns nil on any other shape.
    var parseISO8601Date: @Sendable (String) -> Date?
}

// MARK: - DependencyKey

extension CalendarContext: DependencyKey {
    /// `liveValue` reads `Date()` and `Calendar.autoupdatingCurrent` directly,
    /// NOT via `@Dependency(\.date)` / `@Dependency(\.calendar)`.
    ///
    /// This is intentional. `CalendarContext` IS the clock seam for this app —
    /// it exists so production code stops calling `Date()` ad hoc and starts
    /// going through one Sendable abstraction. Layering swift-dependencies'
    /// `\.date` and `\.calendar` underneath CalendarContext adds a second seam
    /// that the test runtime polices: during a test bundle launch, the host app
    /// boots, the bootstrap path installs live values, and any live closure that
    /// touches `@Dependency(\.date)` trips swift-dependencies' "no test
    /// implementation" XCTFail — even though the failure originated in host-app
    /// launch, not in a test. (See swift-dependencies "Testing gotchas".)
    ///
    /// The CLAUDE.md rule "no bare `Date()`" is about production *call sites* —
    /// not about the one foundational dependency whose entire job is to wrap
    /// the system clock. Tests override `CalendarContext` itself via
    /// `withDependencies { $0.calendarContext = .fixed(now: ...) }`.
    static var liveValue: CalendarContext {
        CalendarContext(
            now: { Date() },
            userCalendar: { Calendar.autoupdatingCurrent },
            userTimeZone: { .autoupdatingCurrent },
            userLocale: { .autoupdatingCurrent },
            dayKey: { d in
                var greg = Calendar(identifier: .gregorian)
                greg.timeZone = .autoupdatingCurrent
                let c = greg.dateComponents([.year, .month, .day], from: d)
                guard let y = c.year, let m = c.month, let day = c.day else {
                    preconditionFailure(
                        "dateComponents([.year,.month,.day]) returned partial result"
                    )
                }
                return String(format: "%04d-%02d-%02d", y, m, day)
            },
            startOfDay: { d in Calendar.autoupdatingCurrent.startOfDay(for: d) },
            isSameDay: { a, b in Calendar.autoupdatingCurrent.isDate(a, inSameDayAs: b) },
            isToday: { d in Calendar.autoupdatingCurrent.isDateInToday(d) },
            add: { component, value, d in
                guard let result = Calendar.autoupdatingCurrent.date(
                    byAdding: component, value: value, to: d
                ) else {
                    preconditionFailure(
                        "Calendar.date(byAdding: \(component), value: \(value)) returned nil."
                    )
                }
                return result
            },
            parseISO8601Date: { string in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                formatter.timeZone = .autoupdatingCurrent
                return formatter.date(from: string)
            }
        )
    }

    static var testValue: CalendarContext {
        CalendarContext.fixed(
            now: Date(timeIntervalSince1970: 1_778_803_200)
        )
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    var calendarContext: CalendarContext {
        get { self[CalendarContext.self] }
        set { self[CalendarContext.self] = newValue }
    }
}

// MARK: - Fixed factory for tests

extension CalendarContext {
    /// Build a fixed-clock context for tests. All helpers use real Calendar
    /// operations against the frozen `now`. Substitute via `withDependencies`.
    static func fixed(
        now: Date,
        timeZone: TimeZone = TimeZone(identifier: "America/New_York")!,
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> CalendarContext {
        var cal = baseCalendar
        cal.timeZone = timeZone
        cal.locale = locale

        return CalendarContext(
            now: { now },
            userCalendar: { cal },
            userTimeZone: { timeZone },
            userLocale: { locale },
            dayKey: { d in
                var greg = Calendar(identifier: .gregorian)
                greg.timeZone = timeZone
                let c = greg.dateComponents([.year, .month, .day], from: d)
                guard let y = c.year, let m = c.month, let day = c.day else {
                    preconditionFailure("partial date components")
                }
                return String(format: "%04d-%02d-%02d", y, m, day)
            },
            startOfDay: { d in cal.startOfDay(for: d) },
            isSameDay: { a, b in cal.isDate(a, inSameDayAs: b) },
            isToday: { d in cal.isDate(d, inSameDayAs: now) },
            add: { component, value, d in
                guard let result = cal.date(byAdding: component, value: value, to: d) else {
                    preconditionFailure("calendar add nil")
                }
                return result
            },
            parseISO8601Date: { string in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                formatter.timeZone = timeZone
                return formatter.date(from: string)
            }
        )
    }
}
