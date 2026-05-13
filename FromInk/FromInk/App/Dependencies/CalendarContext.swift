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
    static var liveValue: CalendarContext {
        @Dependency(\.date) var date
        @Dependency(\.calendar) var calendar

        return CalendarContext(
            now: { date.now },
            userCalendar: { calendar },
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
            startOfDay: { d in calendar.startOfDay(for: d) },
            isSameDay: { a, b in calendar.isDate(a, inSameDayAs: b) },
            isToday: { d in calendar.isDateInToday(d) },
            add: { component, value, d in
                guard let result = calendar.date(byAdding: component, value: value, to: d) else {
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
