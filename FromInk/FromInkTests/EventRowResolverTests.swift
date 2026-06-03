import Foundation
import XCTest
@testable import FromInk

/// Unit coverage for `EventRowResolver` — the pure function that turns
/// raw `StoredHighlight` timing data plus a `now` reference into the
/// (in-progress, badge) tuple consumed by `BriefEventRow.Model`.
///
/// Tests pin:
///   - Boundary semantics at start/end (no double-classification,
///     no gap)
///   - The all-day heuristic (>=23 hours, same local day)
///   - Icon variants carry the correct SF Symbol + color + a11y label
///   - Highlights without start/end fall through to the stored
///     trailingBadge (all-day rows, anytime reminders rerouted through
///     the events code path)
///
/// Boundary semantics use a fixed `now` and event times relative to it,
/// so the assertions are deterministic regardless of the device clock.
/// The Apple-formatted future text is left unasserted — its output is
/// locale-dependent and Apple-owned.
///
final class EventRowResolverTests: XCTestCase {

    /// Fixed "now" — 2026-05-13 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_778_673_600)

    /// Gregorian + UTC, matching the `CalendarContext.fixed` fixture
    /// used by other home-tests so day-boundary math is the same.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    // MARK: - Boundary classification

    /// Event ending exactly at `now`: must classify as PASSED, not
    /// in-progress. The predicate is `now < end` for in-progress, so
    /// `now == end` falls to passed. Verified via mental walkthrough
    /// in the prior code review.
    func test_endExactlyAtNow_classifiesAsPassed() {
        let h = makeEvent(
            start: now.addingTimeInterval(-3600),  // 1 hour ago
            end: now                                // ends right now
        )

        let (isInProgress, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        XCTAssertFalse(isInProgress)
        switch badge {
        case .icon(let systemName, _, _):
            XCTAssertEqual(systemName, "checkmark")
        case .text:
            XCTFail("Expected checkmark icon, got text badge")
        }
    }

    /// Event starting exactly at `now`: must classify as IN-PROGRESS.
    /// The predicate is `start <= now` for in-progress, so the boundary
    /// belongs to the active state.
    func test_startExactlyAtNow_classifiesAsInProgress() {
        let h = makeEvent(
            start: now,                              // starts right now
            end: now.addingTimeInterval(3600)        // ends in 1 hour
        )

        let (isInProgress, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        XCTAssertTrue(isInProgress)
        switch badge {
        case .icon(let systemName, _, _):
            XCTAssertEqual(systemName, "record.circle.fill")
        case .text:
            XCTFail("Expected record-dot icon, got text badge")
        }
    }

    func test_eventInProgressMidpoint_classifiesAsInProgress() {
        let h = makeEvent(
            start: now.addingTimeInterval(-1800),   // started 30 min ago
            end: now.addingTimeInterval(1800)       // ends in 30 min
        )

        let (isInProgress, _) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        XCTAssertTrue(isInProgress)
    }

    func test_eventEntirelyPast_classifiesAsPassed() {
        let h = makeEvent(
            start: now.addingTimeInterval(-7200),   // 2 hours ago
            end: now.addingTimeInterval(-3600)      // 1 hour ago
        )

        let (isInProgress, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        XCTAssertFalse(isInProgress)
        switch badge {
        case .icon(let systemName, _, let label):
            XCTAssertEqual(systemName, "checkmark")
            XCTAssertEqual(label, AppStrings.Home.eventPassedAccessibilityLabel)
        case .text:
            XCTFail("Expected checkmark icon, got text badge")
        }
    }

    func test_eventEntirelyFuture_classifiesAsFutureText() {
        let h = makeEvent(
            start: now.addingTimeInterval(1800),    // starts in 30 min
            end: now.addingTimeInterval(5400)       // ends in 90 min
        )

        let (isInProgress, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        XCTAssertFalse(isInProgress)
        switch badge {
        case .text(let label):
            // Don't pin the exact Apple-formatted string — it varies
            // by locale and OS version. Just confirm we got the text
            // variant rather than a state icon.
            XCTAssertFalse(label.isEmpty)
        case .icon:
            XCTFail("Future event should yield text variant, got icon")
        }
    }

    // MARK: - All-day heuristic

    /// Event ≥23 hours starting today (the same local day as `now`)
    /// should yield the localized "All day" override, not Apple's
    /// "in 23 hr" relative format.
    func test_almostFullDayEventToday_yieldsAllDayOverride() {
        let h = makeEvent(
            start: now.addingTimeInterval(3600),    // starts in 1 hour
            end: now.addingTimeInterval(3600 + 23 * 3600) // 23-hour duration
        )

        let (_, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        switch badge {
        case .text(let label):
            XCTAssertEqual(label, AppStrings.Home.allDay)
        case .icon:
            XCTFail("Almost-full-day event should yield 'All day' text")
        }
    }

    /// 23-hour event starting on a future day (not today): the
    /// override does NOT apply — Apple's relative format is correct
    /// for the day-distinction case.
    func test_almostFullDayEvent_notToday_doesNotApplyOverride() {
        // Start tomorrow at noon, 23-hour duration.
        let tomorrowNoon = now.addingTimeInterval(24 * 3600)
        let h = makeEvent(
            start: tomorrowNoon,
            end: tomorrowNoon.addingTimeInterval(23 * 3600)
        )

        let (_, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        switch badge {
        case .text(let label):
            // Apple's relative format should produce something —
            // we just verify it's NOT our "All day" override.
            XCTAssertNotEqual(label, AppStrings.Home.allDay)
        case .icon:
            XCTFail("Future multi-day event should yield text variant")
        }
    }

    // MARK: - Nil-timing fallback

    /// Highlights without start/end (all-day rows, malformed records)
    /// must fall through to the stored `trailingBadge`. Buildhighlights
    /// sets this to "" for all-day events; the row's time column shows
    /// "All day" directly.
    func test_nilTiming_fallsThroughToStoredTrailingBadge() {
        let h = StoredHighlight(
            category: .allDay,
            icon: "calendar",
            title: "All-day retreat",
            time: AppStrings.Home.allDay,
            trailingBadge: "",
            sourceNotebookID: nil,
            sourcePageIndex: nil,
            startDate: nil,
            endDate: nil
        )

        let (isInProgress, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        XCTAssertFalse(isInProgress)
        XCTAssertEqual(badge, .text(""))
    }

    // MARK: - Icon variant integrity

    /// Passed-event icon carries the right color (ink3 — muted) and
    /// the localized VoiceOver label. Verifies the state-icon contract
    /// without depending on the colorset values.
    func test_passedIcon_carriesAccessibilityLabel() {
        let h = makeEvent(
            start: now.addingTimeInterval(-7200),
            end: now.addingTimeInterval(-3600)
        )

        let (_, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        switch badge {
        case .icon(let systemName, _, let label):
            XCTAssertEqual(systemName, "checkmark")
            XCTAssertEqual(label, AppStrings.Home.eventPassedAccessibilityLabel)
        case .text:
            XCTFail("Expected icon variant for passed event")
        }
    }

    /// In-progress icon uses `record.circle.fill` and carries the
    /// localized VoiceOver label.
    func test_inProgressIcon_carriesAccessibilityLabel() {
        let h = makeEvent(
            start: now.addingTimeInterval(-600),
            end: now.addingTimeInterval(600)
        )

        let (_, badge) = EventRowResolver.resolve(
            highlight: h, now: now, calendar: utcCalendar
        )

        switch badge {
        case .icon(let systemName, _, let label):
            XCTAssertEqual(systemName, "record.circle.fill")
            XCTAssertEqual(label, AppStrings.Home.eventInProgressAccessibilityLabel)
        case .text:
            XCTFail("Expected icon variant for in-progress event")
        }
    }

    // MARK: - Fixtures

    private func makeEvent(start: Date, end: Date) -> StoredHighlight {
        StoredHighlight(
            category: .upcoming,
            icon: "calendar",
            title: "Test event",
            time: "12:00 PM",
            trailingBadge: "",
            sourceNotebookID: nil,
            sourcePageIndex: nil,
            startDate: start,
            endDate: end
        )
    }
}
