import ComposableArchitecture
import Foundation
import os

/// Subscribes to `EKEventStoreChanged` and reconciles persisted
/// `CalendarItemLink` records against EventKit's current state. Two
/// outcomes per link per pass:
///
///   1. **Heal stale local IDs.** The user moves an event between
///      calendars → EventKit issues a new `eventIdentifier` → our
///      `localIdentifier` no longer resolves. `externalIdentifier`
///      (iCloud / CalDAV) usually carries over; resolving by external
///      ID gives us the new local ID, and we rewrite the link in
///      place. The notebook keeps working without user intervention.
///
///   2. **Drop orphans.** Both local + external lookups fail → the
///      calendar item is gone (deleted in Calendar.app, or removed by
///      a sync). Delete the link record only. **Never touch the
///      notebook** — the notebook survives event deletion is the
///      project requirement that justifies this validator.
///
/// Runs in the background (off the brief generation hot path) — it's a
/// data-integrity sweeper, not a request handler. Cadence: once per
/// `EKEventStoreChanged` burst, debounced to 2 seconds so bulk edits in
/// Calendar.app don't cause us to spam EKEventStore with N lookups
/// during the burst.
///
struct CalendarItemLinkValidator: Sendable {
    /// Long-lived subscription. Drains forever — caller cancels the
    /// effect on app teardown. The closure runs one validation pass
    /// per debounced change event.
    var observeAndReconcile: @Sendable () async -> Void
}

// MARK: - DependencyValues

extension DependencyValues {
    var calendarItemLinkValidator: CalendarItemLinkValidator {
        get { self[CalendarItemLinkValidator.self] }
        set { self[CalendarItemLinkValidator.self] = newValue }
    }
}

// MARK: - DependencyKey

extension CalendarItemLinkValidator: DependencyKey {
    /// `liveValue` is unwired — the live instance composes services
    /// (`EventKitService`, `DailyBriefClient`, `CalendarItemLinkService`,
    /// `ContinuousClock`) and is built in `AppDependencyContainer`.
    /// Calling this before install is a programming error.
    static let liveValue: CalendarItemLinkValidator = CalendarItemLinkValidator(
        observeAndReconcile: {
            fatalError(
                "calendarItemLinkValidator.liveValue accessed before install. " +
                "Call AppDependencyContainer.install(into:) at app launch."
            )
        }
    )

    /// `testValue`: no-op. Tests for the validator itself construct one
    /// via `.live(...)` with explicit fake services; everywhere else
    /// the no-op is fine because the validator has no observable
    /// surface beyond its side effects on persistent storage.
    static let testValue: CalendarItemLinkValidator = CalendarItemLinkValidator(
        observeAndReconcile: { }
    )
}

// MARK: - Factory

extension CalendarItemLinkValidator {
    private static let log = Logger(subsystem: "com.fromink.app", category: "CalendarItemLink")

    /// Construct a live validator from its collaborators. Debounce
    /// window: 2 seconds — long enough to coalesce bulk imports
    /// (Calendar.app subscribes to a new feed → N change events in <1s)
    /// without making the user wait noticeably for a single edit to
    /// reflect. Same magnitude as the brief's 1s debounce; chosen
    /// independently because validator work is heavier per pass.
    static func live(
        linkService: CalendarItemLinkService,
        eventKit: EventKitService,
        calendarChanges: @escaping @Sendable () -> AsyncStream<Void>,
        clock: any Clock<Duration>,
        debounceWindow: Duration = .seconds(2)
    ) -> CalendarItemLinkValidator {
        CalendarItemLinkValidator(
            observeAndReconcile: {
                // Manual cancel-and-restart debounce. On each upstream
                // signal we cancel any in-flight pending Task and
                // schedule a new one to fire after `debounceWindow`.
                // If another signal arrives during the sleep, that
                // Task's `clock.sleep` throws and the cancellation
                // check below skips the reconcile.
                //
                // The project doesn't depend on swift-async-algorithms,
                // so the obvious `.debounce(for:clock:)` operator isn't
                // available. Rolling it with a single tracked Task is a
                // few lines and keeps the dependency graph thin.
                let stream = calendarChanges()
                var pendingTask: Task<Void, Never>?

                for await _ in stream {
                    pendingTask?.cancel()
                    pendingTask = Task {
                        try? await clock.sleep(for: debounceWindow)
                        guard !Task.isCancelled else { return }
                        await reconcile(linkService: linkService, eventKit: eventKit)
                    }
                }

                pendingTask?.cancel()
            }
        )
    }

    /// One validation pass. Visible at file scope so tests can call it
    /// directly without going through the AsyncStream plumbing.
    static func reconcile(
        linkService: CalendarItemLinkService,
        eventKit: EventKitService
    ) async {
        let links = await linkService.allLinks()
        guard !links.isEmpty else { return }

        log.info("Validator pass: examining \(links.count) link(s)")

        var healed = 0
        var dropped = 0

        for link in links {
            let resolution = await eventKit.resolveCalendarItem(
                link.localIdentifier,
                link.externalIdentifier,
                link.kind
            )

            guard let resolution else {
                // Orphan — both local + external lookups failed. Drop
                // the link record; the notebook is untouched by design.
                do {
                    try await linkService.delete(link.id)
                    dropped += 1
                } catch {
                    log.error("Orphan delete failed for \(link.id, privacy: .public): \(error.localizedDescription)")
                }
                continue
            }

            // Heal stale identifiers in place. Most passes won't touch
            // the link — only when EK reports a different local ID
            // (move-between-calendars) or surfaces an external ID we
            // didn't have before.
            let localChanged = resolution.localIdentifier != link.localIdentifier
            let externalChanged = resolution.externalIdentifier != link.externalIdentifier
            if localChanged || externalChanged {
                do {
                    try await linkService.rewriteIdentifiers(
                        link.id,
                        resolution.localIdentifier,
                        resolution.externalIdentifier
                    )
                    healed += 1
                } catch {
                    log.error("Failed to heal link \(link.id, privacy: .public): \(error.localizedDescription)")
                }
            }
        }

        if healed > 0 || dropped > 0 {
            log.info("Validator pass complete: healed=\(healed), dropped=\(dropped)")
        }
    }
}
