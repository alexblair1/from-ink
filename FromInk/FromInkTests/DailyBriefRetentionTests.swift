import SwiftData
import XCTest
@testable import FromInk

/// Exercises `DailyBriefRetention.touchIfStale` and
/// `.evictIfNeeded` directly against an in-memory `ModelContainer`,
/// the SwiftData-native pattern for testing model logic without
/// disk or CloudKit involvement.
///
/// Policy details live in `Documentation/data_model_edd.md §11
/// Retention`. These tests pin the behavior that section describes
/// — staleness debounce, LRU ordering, and the hysteresis band.
///
final class DailyBriefRetentionTests: XCTestCase {

    /// Fixed reference moment used as the base timestamp for every
    /// record in the suite. Avoids `Date()` so tests stay
    /// deterministic across time-zone and clock drift.
    private let baseDate = Date(timeIntervalSince1970: 1_778_000_000)

    // MARK: - Helpers

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DailyBriefRecord.self, configurations: config)
        return ModelContext(container)
    }

    /// Inserts a record with explicit `lastAccessedAt` so each test
    /// can construct a deterministic LRU ordering.
    @MainActor
    private func insertRecord(
        dayKey: String,
        lastAccessedAt: Date,
        into context: ModelContext
    ) {
        let record = DailyBriefRecord(
            dayKey: dayKey,
            focusText: "brief for \(dayKey)",
            suggestionText: "",
            eventCountAtGeneration: 0,
            reminderCountAtGeneration: 0,
            generatedAt: lastAccessedAt,
            lastAccessedAt: lastAccessedAt
        )
        context.insert(record)
    }

    @MainActor
    private func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<DailyBriefRecord>())
    }

    @MainActor
    private func dayKeys(in context: ModelContext) throws -> [String] {
        let records = try context.fetch(
            FetchDescriptor<DailyBriefRecord>(
                sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
            )
        )
        return records.map(\.dayKey)
    }

    // MARK: - touchIfStale

    @MainActor
    func test_touchIfStale_updatesWhenOlderThanInterval() throws {
        let context = try makeContext()
        let now = baseDate.addingTimeInterval(7_200)   // 2h after baseDate
        insertRecord(dayKey: "2026-05-13", lastAccessedAt: baseDate, into: context)
        try context.save()

        let record = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyBriefRecord>()).first
        )
        XCTAssertEqual(record.lastAccessedAt, baseDate)

        DailyBriefRetention.touchIfStale(
            record,
            now: now,
            context: context,
            interval: 3_600   // 1h debounce
        )

        XCTAssertEqual(record.lastAccessedAt, now)
    }

    @MainActor
    func test_touchIfStale_noOpWhenWithinInterval() throws {
        let context = try makeContext()
        let now = baseDate.addingTimeInterval(1_800)   // 30 minutes after
        insertRecord(dayKey: "2026-05-13", lastAccessedAt: baseDate, into: context)
        try context.save()

        let record = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyBriefRecord>()).first
        )

        DailyBriefRetention.touchIfStale(
            record,
            now: now,
            context: context,
            interval: 3_600   // 1h debounce — 30 min is inside the window
        )

        XCTAssertEqual(
            record.lastAccessedAt, baseDate,
            "Touch within the debounce window must leave the timestamp unchanged"
        )
    }

    // MARK: - evictIfNeeded

    @MainActor
    func test_evictIfNeeded_noOpBelowThreshold() throws {
        let context = try makeContext()
        for i in 0..<5 {
            insertRecord(
                dayKey: dayKey(offset: i),
                lastAccessedAt: baseDate.addingTimeInterval(Double(i) * 3_600),
                into: context
            )
        }
        try context.save()
        XCTAssertEqual(try count(in: context), 5)

        DailyBriefRetention.evictIfNeeded(context: context, threshold: 10, target: 8)

        XCTAssertEqual(
            try count(in: context), 5,
            "Below threshold: evictIfNeeded must be a no-op"
        )
    }

    @MainActor
    func test_evictIfNeeded_noOpAtThreshold() throws {
        let context = try makeContext()
        for i in 0..<10 {
            insertRecord(
                dayKey: dayKey(offset: i),
                lastAccessedAt: baseDate.addingTimeInterval(Double(i) * 3_600),
                into: context
            )
        }
        try context.save()

        DailyBriefRetention.evictIfNeeded(context: context, threshold: 10, target: 8)

        XCTAssertEqual(
            try count(in: context), 10,
            "Exactly at threshold: evictIfNeeded must be a no-op (rule is strict `>`)"
        )
    }

    @MainActor
    func test_evictIfNeeded_evictsOldestDownToTarget() throws {
        let context = try makeContext()
        for i in 0..<12 {
            insertRecord(
                dayKey: dayKey(offset: i),
                lastAccessedAt: baseDate.addingTimeInterval(Double(i) * 3_600),
                into: context
            )
        }
        try context.save()
        XCTAssertEqual(try count(in: context), 12)

        DailyBriefRetention.evictIfNeeded(context: context, threshold: 10, target: 8)

        XCTAssertEqual(
            try count(in: context), 8,
            "Above threshold: evictIfNeeded must drop the count to `target`"
        )

        // The 4 oldest (offsets 0-3) should be gone; offsets 4-11 remain
        // ordered by lastAccessedAt ascending.
        let remaining = try dayKeys(in: context)
        XCTAssertEqual(remaining.first, dayKey(offset: 4), "Oldest survivor is offset 4")
        XCTAssertEqual(remaining.last, dayKey(offset: 11), "Newest survivor is offset 11")
        XCTAssertEqual(remaining.count, 8)
    }

    @MainActor
    func test_evictIfNeeded_oneOverThreshold_evictsHysteresisBand() throws {
        // 11 records, threshold 10, target 8 → eviction fires and
        // removes 3 records in one pass, not 1. Pins the hysteresis
        // behavior described in §11.2.
        let context = try makeContext()
        for i in 0..<11 {
            insertRecord(
                dayKey: dayKey(offset: i),
                lastAccessedAt: baseDate.addingTimeInterval(Double(i) * 3_600),
                into: context
            )
        }
        try context.save()

        DailyBriefRetention.evictIfNeeded(context: context, threshold: 10, target: 8)

        XCTAssertEqual(
            try count(in: context), 8,
            "11 → 8 in one pass (count - target = 3 records removed)"
        )
    }

    // MARK: - Day-key helper

    /// Stable synthetic day-key for ordering tests — `2026-05-XX`.
    /// Padded to keep lexical and chronological order aligned.
    private func dayKey(offset: Int) -> String {
        let day = String(format: "%02d", offset + 1)
        return "2026-05-\(day)"
    }
}
