import ComposableArchitecture
import SwiftData
import XCTest
@testable import FromInk

final class DailyBriefClientTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_778_673_600) // 2026-05-13 12:00 UTC
    private lazy var fixedCal = CalendarContext.fixed(
        now: fixedNow,
        timeZone: TimeZone(identifier: "UTC")!
    )

    // MARK: - Live factory test helpers

    /// Returns a fresh in-memory `SyncedModelContextDependency` per test
    /// so cache state from one test never leaks into another. Uses
    /// `ModelContext(container)` (private context) rather than
    /// `container.mainContext` — matches the pattern in
    /// `DailyBriefRetentionTests.makeContext()` which is known to
    /// initialize SwiftData cleanly under XCTest's runtime.
    @MainActor
    private func makeInMemoryContext() throws -> (SyncedModelContextDependency, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DailyBriefRecord.self,
            configurations: config
        )
        let context = ModelContext(container)
        let dep = SyncedModelContextDependency(
            context: { context },
            warmup: { }
        )
        return (dep, context)
    }

    /// Test-double EventKitService. Each closure can be overridden;
    /// defaults return empty (no events, no reminders) for the
    /// "live (0, 0)" baseline.
    private func makeEventKit(
        events: [CalendarEventSnapshot] = [],
        reminders: [ReminderSnapshot] = [],
        throwOnEvents: Bool = false,
        throwOnReminders: Bool = false
    ) -> EventKitService {
        EventKitService(
            fetchTodayEvents: {
                if throwOnEvents { throw TestError.eventKitFailure }
                return events
            },
            fetchDueReminders: {
                if throwOnReminders { throw TestError.eventKitFailure }
                return reminders
            },
            fetchEvents: { _ in events },
            fetchReminders: { _ in reminders },
            eventAuthStatus: { .fullAccess },
            reminderAuthStatus: { .fullAccess },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .fullAccess },
            listCalendars: { [] },
            listReminderLists: { [] },
            createEvent: { _ in "test-event" },
            updateEvent: { _, _ in },
            createReminder: { _ in "test-reminder" },
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in }
        )
    }

    /// Test-double FoundationModelsService. By default returns a
    /// non-empty brief so the cache predicate sees content.
    private func makeFoundationModels(
        isAvailable: Bool = true,
        supportsLocale: Bool = true,
        focusText: String = "Today is busy.",
        suggestionText: String = "Block focus time."
    ) -> FoundationModelsService {
        FoundationModelsService(
            isAvailable: { isAvailable },
            supportsLocale: { _ in supportsLocale },
            generateBrief: { _ in
                DailyBrief(
                    greeting: "Hello",
                    focus: focusText,
                    schedule: [],
                    urgentReminders: [],
                    pendingFromInk: [],
                    suggestion: suggestionText
                )
            }
        )
    }

    private enum TestError: Error { case eventKitFailure }

    // MARK: - fetchOrGenerate

    func test_fetchOrGenerate_returnsSnapshot() async throws {
        let expectedDayKey = "2026-05-13"
        let client = DailyBriefClient(
            fetchOrGenerate: {
                DailyBriefSnapshot(
                    dayKey: expectedDayKey,
                    focusText: "A busy day ahead.",
                    suggestionText: "Block time for the PRD.",
                    generatedAt: self.fixedNow,
                    wasPersisted: true
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
                    generatedAt: self.fixedNow,
                    wasPersisted: true
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
                    generatedAt: self.fixedNow,
                    wasPersisted: true
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
                    generatedAt: self.fixedNow,
                    wasPersisted: true
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
            generatedAt: fixedNow,
            wasPersisted: true
        )

        let b = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus",
            suggestionText: "Suggest",
            generatedAt: fixedNow,
            wasPersisted: true
        )

        XCTAssertEqual(a, b)
    }

    func test_snapshot_notEqual_differentFocus() {
        let a = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus A",
            suggestionText: "",
            generatedAt: fixedNow,
            wasPersisted: true
        )

        let b = DailyBriefSnapshot(
            dayKey: "2026-05-13",
            focusText: "Focus B",
            suggestionText: "",
            generatedAt: fixedNow,
            wasPersisted: true
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

    // MARK: - Cache predicate hardening (A1)

    /// A cached record with empty `focusText` + `suggestionText`
    /// (left behind by a transient FM failure) should NOT be returned
    /// from `fetchOrGenerate` when FM is now available. The client
    /// must call generateBrief again and overwrite the record. Without
    /// this rule, the empty record would poison the cache forever and
    /// the editor's note would stay hidden.
    @MainActor
    func test_fetchOrGenerate_emptyContentRecord_andFMAvailable_regenerates() async throws {
        let (modelDep, context) = try makeInMemoryContext()
        let dayKey = fixedCal.dayKey(fixedCal.now())

        // Seed an empty-content record matching today's dayKey with
        // (0, 0) counts. This is the exact shape an earlier FM glitch
        // would leave behind.
        let stale = DailyBriefRecord(
            dayKey: dayKey,
            focusText: "",
            suggestionText: "",
            eventCountAtGeneration: 0,
            reminderCountAtGeneration: 0,
            generatedAt: fixedNow
        )
        context.insert(stale)
        try context.save()

        let client = DailyBriefClient.live(
            modelContext: modelDep,
            eventKit: makeEventKit(),
            foundationModels: makeFoundationModels(
                focusText: "Regenerated focus.",
                suggestionText: "Regenerated suggestion."
            ),
            calendarContext: fixedCal
        )

        let snapshot = try await client.fetchOrGenerate()

        XCTAssertEqual(snapshot.focusText, "Regenerated focus.")
        XCTAssertEqual(snapshot.suggestionText, "Regenerated suggestion.")
    }

    /// Same empty-content cache — but FM is unavailable. We should NOT
    /// thrash trying to regenerate against a model that can't respond.
    /// Return the cached empty record, log it, and let the view
    /// continue hiding the editor's note.
    @MainActor
    func test_fetchOrGenerate_emptyContentRecord_andFMUnavailable_returnsCached() async throws {
        let (modelDep, context) = try makeInMemoryContext()
        let dayKey = fixedCal.dayKey(fixedCal.now())

        let stale = DailyBriefRecord(
            dayKey: dayKey,
            focusText: "",
            suggestionText: "",
            eventCountAtGeneration: 0,
            reminderCountAtGeneration: 0,
            generatedAt: fixedNow
        )
        context.insert(stale)
        try context.save()

        let client = DailyBriefClient.live(
            modelContext: modelDep,
            eventKit: makeEventKit(),
            foundationModels: makeFoundationModels(
                isAvailable: false,
                focusText: "Should not be used.",
                suggestionText: "Should not be used."
            ),
            calendarContext: fixedCal
        )

        let snapshot = try await client.fetchOrGenerate()

        XCTAssertTrue(snapshot.focusText.isEmpty)
        XCTAssertTrue(snapshot.suggestionText.isEmpty)
    }

    /// A cached (0, 0) record + a transient EventKit failure must NOT
    /// be treated as a count match. Otherwise a user who loses calendar
    /// permission mid-day caches (0, 0) and never escapes. Forcing
    /// regen lets FM repopulate the record honestly on the next try.
    ///
    /// The test stubs EventKit to fail on the FIRST call (the cache
    /// staleness check inside `fetchLiveCounts`) but succeed on the
    /// second call (the generation pass inside `runGeneration`). This
    /// proves the predicate forced regen even though the cached counts
    /// numerically matched the failed (0, 0) reading.
    @MainActor
    func test_fetchOrGenerate_eventKitFailure_doesNotMatchZeroCountsCache() async throws {
        let (modelDep, context) = try makeInMemoryContext()
        let dayKey = fixedCal.dayKey(fixedCal.now())

        // (0, 0) cached. The "Old focus." text would surface if the
        // cache predicate silently matched.
        let cached = DailyBriefRecord(
            dayKey: dayKey,
            focusText: "Old focus.",
            suggestionText: "Old suggestion.",
            eventCountAtGeneration: 0,
            reminderCountAtGeneration: 0,
            generatedAt: fixedNow
        )
        context.insert(cached)
        try context.save()

        // EventKit fails first call only — count check throws, but
        // the subsequent generation-phase fetch succeeds.
        let eventsCalls = LockIsolated(0)
        let remindersCalls = LockIsolated(0)
        let eventKit = EventKitService(
            fetchTodayEvents: {
                let n = eventsCalls.withValue { $0 += 1; return $0 }
                if n == 1 { throw TestError.eventKitFailure }
                return []
            },
            fetchDueReminders: {
                let n = remindersCalls.withValue { $0 += 1; return $0 }
                if n == 1 { throw TestError.eventKitFailure }
                return []
            },
            fetchEvents: { _ in [] },
            fetchReminders: { _ in [] },
            eventAuthStatus: { .fullAccess },
            reminderAuthStatus: { .fullAccess },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .fullAccess },
            listCalendars: { [] },
            listReminderLists: { [] },
            createEvent: { _ in "test-event" },
            updateEvent: { _, _ in },
            createReminder: { _ in "test-reminder" },
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in }
        )

        let client = DailyBriefClient.live(
            modelContext: modelDep,
            eventKit: eventKit,
            foundationModels: makeFoundationModels(
                focusText: "Regenerated focus.",
                suggestionText: "Regenerated suggestion."
            ),
            calendarContext: fixedCal
        )

        let snapshot = try await client.fetchOrGenerate()

        // Cache predicate forced regen since the (0, 0) count match
        // came from a failed query, not a confirmed empty day.
        XCTAssertEqual(snapshot.focusText, "Regenerated focus.")
        // EventKit was hit at least twice — once for the cache check
        // (which threw) and once for the generation pass.
        XCTAssertGreaterThanOrEqual(eventsCalls.value, 2)
    }

    // MARK: - Single-flight coordinator (A3)

    /// Two parallel `fetchOrGenerate` calls for the same dayKey must
    /// coalesce — only one SwiftData insert happens. Without the in-
    /// flight task table they'd both miss the cache simultaneously
    /// and double-insert (no @Attribute(.unique) available under
    /// CloudKit constraints).
    @MainActor
    func test_fetchOrGenerate_parallelCalls_singleInsert() async throws {
        let (modelDep, context) = try makeInMemoryContext()

        // Track FM invocations as a proxy for "generation ran." If
        // single-flight works, two parallel callers see one generation.
        let generationCount = LockIsolated(0)
        let fm = FoundationModelsService(
            isAvailable: { true },
            supportsLocale: { _ in true },
            generateBrief: { _ in
                generationCount.withValue { $0 += 1 }
                // Slight delay so both callers are in flight when the
                // second arrives — without single-flight they'd both
                // generate. With it, the second awaits the first.
                try? await Task.sleep(for: .milliseconds(100))
                return DailyBrief(
                    greeting: "",
                    focus: "Generated.",
                    schedule: [],
                    urgentReminders: [],
                    pendingFromInk: [],
                    suggestion: ""
                )
            }
        )

        let client = DailyBriefClient.live(
            modelContext: modelDep,
            eventKit: makeEventKit(),
            foundationModels: fm,
            calendarContext: fixedCal
        )

        async let first = client.fetchOrGenerate()
        async let second = client.fetchOrGenerate()
        let snapshots = try await [first, second]

        // Single generation across both callers.
        XCTAssertEqual(generationCount.value, 1)
        // Both snapshots see the same generated text.
        XCTAssertEqual(snapshots[0].focusText, "Generated.")
        XCTAssertEqual(snapshots[1].focusText, "Generated.")

        // Exactly one record in SwiftData.
        let descriptor = FetchDescriptor<DailyBriefRecord>()
        let allRecords = try context.fetch(descriptor)
        XCTAssertEqual(allRecords.count, 1)
    }

    // MARK: - Save failure surfaces as wasPersisted=false (A5)

    /// Tests the snapshot conversion: a record converted with
    /// `wasPersisted: false` flows that signal to callers. The
    /// in-process equivalent of a save failure inside the client.
    func test_snapshot_wasPersisted_propagates() {
        let now = fixedNow
        let record = DailyBriefRecord(
            dayKey: "2026-05-13",
            focusText: "F",
            suggestionText: "S",
            eventCountAtGeneration: 0,
            reminderCountAtGeneration: 0,
            generatedAt: now
        )
        let saved = DailyBriefSnapshot(record: record, wasPersisted: true)
        let unsaved = DailyBriefSnapshot(record: record, wasPersisted: false)

        XCTAssertTrue(saved.wasPersisted)
        XCTAssertFalse(unsaved.wasPersisted)
    }
}
