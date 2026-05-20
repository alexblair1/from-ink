import SwiftData
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "DailyBriefRetention")

/// Retention policy helpers for `DailyBriefRecord`. Extracted into their
/// own namespace so they can be exercised directly against an in-memory
/// `ModelContainer` in tests — file-private functions inside
/// `DailyBriefClient` aren't reachable even with `@testable import`.
///
/// Policy details and rationale live in
/// `Documentation/data_model_edd.md §11 Retention`. The static
/// constants on `DailyBriefRecord` are the single source of truth for
/// thresholds; this namespace just acts on them.
///
enum DailyBriefRetention {

    /// Updates `lastAccessedAt` on a cache hit, debounced to one write
    /// per `interval`. Without the debounce we'd dirty the store (and
    /// CloudKit) on every appeared / foregrounded / wheel scroll —
    /// hour-granularity is plenty of signal for LRU ordering.
    ///
    /// `interval` is parameterized so tests can use small values
    /// without manipulating clocks; production calls use the default.
    @MainActor
    static func touchIfStale(
        _ record: DailyBriefRecord,
        now: Date,
        context: ModelContext,
        interval: TimeInterval = DailyBriefRecord.touchInterval
    ) {
        guard now.timeIntervalSince(record.lastAccessedAt) > interval else {
            return
        }
        record.lastAccessedAt = now
        do {
            try context.save()
        } catch {
            log.error("touchIfStale: save failed — \(error)")
        }
    }

    /// LRU eviction. When the total record count exceeds `threshold`,
    /// deletes records with the oldest `lastAccessedAt` until the
    /// count drops to `target`. The threshold-to-target gap is a
    /// hysteresis band — without it, every subsequent write at the
    /// threshold would trigger another single-record eviction.
    ///
    /// `threshold` / `target` are parameterized so tests can use small
    /// counts; production calls use the defaults from
    /// `DailyBriefRecord.evictionThreshold` / `.evictionTarget`.
    @MainActor
    static func evictIfNeeded(
        context: ModelContext,
        threshold: Int = DailyBriefRecord.evictionThreshold,
        target: Int = DailyBriefRecord.evictionTarget
    ) {
        let countDescriptor = FetchDescriptor<DailyBriefRecord>()
        guard let totalCount = try? context.fetchCount(countDescriptor) else {
            return
        }
        guard totalCount > threshold else { return }

        let evictCount = totalCount - target
        var oldestDescriptor = FetchDescriptor<DailyBriefRecord>(
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
        )
        oldestDescriptor.fetchLimit = evictCount

        guard let toEvict = try? context.fetch(oldestDescriptor) else { return }
        for record in toEvict {
            context.delete(record)
        }
        do {
            try context.save()
            log.info("evictIfNeeded: removed \(toEvict.count) records — count \(totalCount) → \(target)")
        } catch {
            log.error("evictIfNeeded: save failed — \(error)")
        }
    }
}
