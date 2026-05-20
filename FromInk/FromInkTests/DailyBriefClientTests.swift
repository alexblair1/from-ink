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
                    generatedAt: self.fixedNow
                )
            },
            refresh: { fatalError("Should not be called") },
            fetch: { _ in nil },
            calendarChanges: { AsyncStream { $0.finish() } },
            fetchDayContent: { _ in DayContent(dayKey: "") },
            generateForDay: { _ in throw CancellationError() }
        )

        let snapshot = try await client.fetchOrGenerate()

        XCTAssertEqual(snapshot.dayKey, expectedDayKey)
        XCTAssertEqual(snapshot.focusText, "A busy day ahead.")
        XCTAssertEqual(snapshot.suggestionText, "Block time for the PRD.")
    }

    func test_fetchOrGenerate_emptyCalendar_returnsFallback() async throws {
        let client = DailyBriefClient(
            fetchOrGenerate: {
                DailyBriefSnapshot(
                    dayKey: "2026-05-13",
                    focusText: "No events or reminders today. A clear day for deep work.",
                    suggestionText: "",
                    generatedAt: self.fixedNow
                )
            },
            refresh: { fatalError("Should not be called") },
            fetch: { _ in nil },
            calendarChanges: { AsyncStream { $0.finish() } },
            fetchDayContent: { _ in DayContent(dayKey: "") },
            generateForDay: { _ in throw CancellationError() }
        )

        let snapshot = try await client.fetchOrGenerate()

        XCTAssertFalse(snapshot.focusText.isEmpty)
        XCTAssertTrue(snapshot.suggestionText.isEmpty)
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
                    generatedAt: self.fixedNow
                )
            },
            fetch: { _ in nil },
            calendarChanges: { AsyncStream { $0.finish() } },
            fetchDayContent: { _ in DayContent(dayKey: "") },
            generateForDay: { _ in throw CancellationError() }
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
                    generatedAt: self.fixedNow
                )
            },
            refresh: { fatalError("Should not be called") },
            fetch: { _ in nil },
            calendarChanges: { stream },
            fetchDayContent: { _ in DayContent(dayKey: "") },
            generateForDay: { _ in throw CancellationError() }
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
            category: .nextUp,
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
            category: .upcoming,
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
            generatedAt: fixedNow
        )

        let b = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus",
            suggestionText: "Suggest",
            generatedAt: fixedNow
        )

        XCTAssertEqual(a, b)
    }

    func test_snapshot_notEqual_differentFocus() {
        let a = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus A",
            suggestionText: "",
            generatedAt: fixedNow
        )

        let b = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus B",
            suggestionText: "",
            generatedAt: fixedNow
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
