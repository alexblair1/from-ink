import ComposableArchitecture
import XCTest
@testable import FromInk

final class DailyBriefClientTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_778_673_600) // 2026-05-13 12:00 UTC
    private lazy var fixedCal = CalendarContext.fixed(
        now: fixedNow,
        timeZone: TimeZone(identifier: "UTC")!
    )

    // MARK: - fetchOrGenerate

    func test_fetchOrGenerate_returnsSnapshot() async throws {
        let expectedDayKey = "2026-05-13"
        let client = DailyBriefClient(
            fetchOrGenerate: {
                DailyBriefSnapshot(
                    dayKey: expectedDayKey,
                    focusText: "A busy day ahead.",
                    suggestionText: "Block time for the PRD.",
                    eventCount: 3,
                    reminderCount: 2,
                    generatedAt: self.fixedNow,
                    highlights: [
                        StoredHighlight(
                            category: "Next up",
                            icon: "calendar",
                            title: "Standup",
                            time: "9:00 AM",
                            trailingBadge: "In 1 h",
                            sourceNotebookID: nil,
                            sourcePageIndex: nil
                        )
                    ]
                )
            },
            refresh: { fatalError("Should not be called") },
            fetch: { _ in nil },
            calendarChanges: { AsyncStream { $0.finish() } }
        )

        let snapshot = try await client.fetchOrGenerate()

        XCTAssertEqual(snapshot.dayKey, expectedDayKey)
        XCTAssertEqual(snapshot.focusText, "A busy day ahead.")
        XCTAssertEqual(snapshot.suggestionText, "Block time for the PRD.")
        XCTAssertEqual(snapshot.eventCount, 3)
        XCTAssertEqual(snapshot.reminderCount, 2)
        XCTAssertEqual(snapshot.highlights.count, 1)
        XCTAssertEqual(snapshot.highlights[0].title, "Standup")
        XCTAssertEqual(snapshot.highlights[0].trailingBadge, "In 1 h")
    }

    func test_fetchOrGenerate_emptyCalendar_returnsFallback() async throws {
        let client = DailyBriefClient(
            fetchOrGenerate: {
                DailyBriefSnapshot(
                    dayKey: "2026-05-13",
                    focusText: "No events or reminders today. A clear day for deep work.",
                    suggestionText: "",
                    eventCount: 0,
                    reminderCount: 0,
                    generatedAt: self.fixedNow,
                    highlights: []
                )
            },
            refresh: { fatalError("Should not be called") },
            fetch: { _ in nil },
            calendarChanges: { AsyncStream { $0.finish() } }
        )

        let snapshot = try await client.fetchOrGenerate()

        XCTAssertEqual(snapshot.eventCount, 0)
        XCTAssertEqual(snapshot.reminderCount, 0)
        XCTAssertTrue(snapshot.highlights.isEmpty)
        XCTAssertFalse(snapshot.focusText.isEmpty)
    }

    // MARK: - refresh

    func test_refresh_alwaysRegenerates() async throws {
        let callCount = LockIsolated(0)

        let client = DailyBriefClient(
            fetchOrGenerate: { fatalError("Should not be called") },
            refresh: {
                callCount.withValue { $0 += 1 }
                return DailyBriefSnapshot(
                    dayKey: "2026-05-13",
                    focusText: "Refreshed.",
                    suggestionText: "",
                    eventCount: 1,
                    reminderCount: 0,
                    generatedAt: self.fixedNow,
                    highlights: []
                )
            },
            fetch: { _ in nil },
            calendarChanges: { AsyncStream { $0.finish() } }
        )

        let first = try await client.refresh()
        let second = try await client.refresh()

        XCTAssertEqual(callCount.value, 2)
        XCTAssertEqual(first.focusText, "Refreshed.")
        XCTAssertEqual(second.focusText, "Refreshed.")
    }

    // MARK: - calendarChanges

    func test_calendarChanges_emitsOnYield() async {
        let stream = AsyncStream<Void> { continuation in
            continuation.yield()
            continuation.yield()
            continuation.finish()
        }

        let client = DailyBriefClient(
            fetchOrGenerate: {
                DailyBriefSnapshot(
                    dayKey: "2026-05-13",
                    focusText: "",
                    suggestionText: "",
                    eventCount: 0,
                    reminderCount: 0,
                    generatedAt: self.fixedNow,
                    highlights: []
                )
            },
            refresh: { fatalError("Should not be called") },
            fetch: { _ in nil },
            calendarChanges: { stream }
        )

        var emitCount = 0
        for await _ in client.calendarChanges() {
            emitCount += 1
        }

        XCTAssertEqual(emitCount, 2)
    }

    // MARK: - StoredHighlight

    func test_storedHighlight_roundTripsJSON() throws {
        let highlight = StoredHighlight(
            category: "Next up",
            icon: "calendar",
            title: "Standup",
            time: "9:00 AM",
            trailingBadge: "In 1 h",
            sourceNotebookID: UUID(),
            sourcePageIndex: 3
        )

        let data = try JSONEncoder().encode([highlight])
        let decoded = try JSONDecoder().decode([StoredHighlight].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0], highlight)
    }

    func test_storedHighlight_nilNotebookFields() throws {
        let highlight = StoredHighlight(
            category: "Upcoming",
            icon: "clock",
            title: "Workshop",
            time: "8:00 PM",
            trailingBadge: "In 10 h",
            sourceNotebookID: nil,
            sourcePageIndex: nil
        )

        let data = try JSONEncoder().encode(highlight)
        let decoded = try JSONDecoder().decode(StoredHighlight.self, from: data)

        XCTAssertNil(decoded.sourceNotebookID)
        XCTAssertNil(decoded.sourcePageIndex)
        XCTAssertEqual(decoded, highlight)
    }

    // MARK: - DailyBriefSnapshot

    func test_snapshot_equatable() {
        let a = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus",
            suggestionText: "Suggest",
            eventCount: 2,
            reminderCount: 1,
            generatedAt: fixedNow,
            highlights: []
        )

        let b = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus",
            suggestionText: "Suggest",
            eventCount: 2,
            reminderCount: 1,
            generatedAt: fixedNow,
            highlights: []
        )

        XCTAssertEqual(a, b)
    }

    func test_snapshot_notEqual_differentCounts() {
        let a = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus",
            suggestionText: "",
            eventCount: 2,
            reminderCount: 1,
            generatedAt: fixedNow,
            highlights: []
        )

        let b = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus",
            suggestionText: "",
            eventCount: 3,
            reminderCount: 1,
            generatedAt: fixedNow,
            highlights: []
        )

        XCTAssertNotEqual(a, b)
    }

    // MARK: - DailyBriefRecord

    func test_dayKey_format_fromCalendarContext() {
        let cal = CalendarContext.fixed(
            now: fixedNow,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let dayKey = cal.dayKey(cal.now())
        XCTAssertEqual(dayKey.count, 10)
        XCTAssertEqual(dayKey.filter { $0 == "-" }.count, 2)
        XCTAssertEqual(dayKey, "2026-05-13")
    }
}
