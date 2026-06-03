import ComposableArchitecture
import EventKit
import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.fromink.app", category: "DailyBrief")

struct DailyBriefClient: Sendable {
    var fetchOrGenerate: @Sendable () async throws -> DailyBriefSnapshot
    var refresh: @Sendable () async throws -> DailyBriefSnapshot
    var fetch: @Sendable (String) async -> DailyBriefSnapshot?
    var calendarChanges: @Sendable () -> AsyncStream<Void>

    /// Fetches the lightweight day content (events + reminders + birthdays)
    /// for an arbitrary date — fast, read-only, no Foundation Models.
    /// Used by the Time Warp wheel to populate the tab body as the user
    /// scrubs, without firing brief generation.
    ///
    /// V1 honest scope: returns today's content (via the same pipeline
    /// `fetchOrGenerate` uses for the live counts) when called for today,
    /// and `DayContent.empty(...)` for other dates. EventKit-by-date
    /// queries are a follow-up.
    var fetchDayContent: @Sendable (Date) async -> DayContent

    /// Generates a brief for a specific date — used by `wheelDismissed`
    /// when the wheel settles on a date with no existing record. Slow
    /// (multi-second FM call); only invoked once per never-seen-before
    /// day.
    ///
    /// V1 honest scope: delegates to `fetchOrGenerate` (today only).
    /// Per-date FM generation is a follow-up that requires per-date
    /// EventKit fetching + prompt date injection.
    var generateForDay: @Sendable (Date) async throws -> DailyBriefSnapshot
}

// MARK: - DependencyKey

extension DailyBriefClient: DependencyKey {
    /// Minimal fallback — not a functioning implementation.
    /// The real live client is built via .live() factory in AppDependencyContainer.
    static let liveValue = DailyBriefClient(
        fetchOrGenerate: { throw CancellationError() },
        refresh: { throw CancellationError() },
        fetch: { _ in nil },
        calendarChanges: { AsyncStream { $0.finish() } },
        fetchDayContent: { date in DayContent.empty(dayKey: "") },
        generateForDay: { _ in throw CancellationError() }
    )

    static let testValue = DailyBriefClient(
        fetchOrGenerate: { throw CancellationError() },
        refresh: { throw CancellationError() },
        fetch: { _ in nil },
        calendarChanges: { AsyncStream { $0.finish() } },
        fetchDayContent: { date in DayContent.empty(dayKey: "") },
        generateForDay: { _ in throw CancellationError() }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var dailyBriefClient: DailyBriefClient {
        get { self[DailyBriefClient.self] }
        set { self[DailyBriefClient.self] = newValue }
    }
}

// MARK: - Live factory

extension DailyBriefClient {
    /// Constructs the live client with its dependencies injected.
    /// Called by AppDependencyContainer — never by reducers or views.
    static func live(
        modelContext: SyncedModelContextDependency,
        eventKit: EventKitService,
        foundationModels: FoundationModelsService,
        calendarContext: CalendarContext
    ) -> DailyBriefClient {
        // Single-flight coordinator. Multiple HomeFeature actions can
        // race into `fetchOrGenerate` for the same dayKey — `.appeared`
        // + `.foregrounded`, or two rapid `.calendarChanged` events.
        // Without coordination both calls miss the cache simultaneously
        // and double-insert into SwiftData (no `@Attribute(.unique)`
        // available under CloudKit). The shared task table keyed by
        // dayKey makes the second caller await the first's result.
        //
        // `Sendable`-safe via `LockIsolated`. Tasks are removed when
        // they finish so the table doesn't accumulate.
        let inflight = LockIsolated<[String: Task<DailyBriefSnapshot, any Error>]>([:])

        return DailyBriefClient(
            fetchOrGenerate: {
                let todayKey = calendarContext.dayKey(calendarContext.now())
                // Atomic check-or-insert under the lock. Without
                // wrapping both operations in the same `withValue`
                // block, two callers can both observe the dict as
                // empty before either inserts — defeating the
                // single-flight contract entirely.
                let task = inflight.withValue { dict -> Task<DailyBriefSnapshot, any Error> in
                    if let existing = dict[todayKey] {
                        log.info("fetchOrGenerate: joining in-flight for \(todayKey)")
                        return existing
                    }
                    let newTask = Task<DailyBriefSnapshot, any Error> {
                        defer { inflight.withValue { $0[todayKey] = nil } }
                        return try await _fetchOrGenerate(
                            modelContext: modelContext,
                            eventKit: eventKit,
                            foundationModels: foundationModels,
                            cal: calendarContext
                        )
                    }
                    dict[todayKey] = newTask
                    return newTask
                }
                return try await task.value
            },
            refresh: {
                try await _refresh(
                    modelContext: modelContext,
                    eventKit: eventKit,
                    foundationModels: foundationModels,
                    cal: calendarContext
                )
            },
            fetch: { dayKey in
                await _fetch(forDayKey: dayKey, modelContext: modelContext, cal: calendarContext)
            },
            calendarChanges: {
                AsyncStream { continuation in
                    let center = NotificationCenter.default
                    let observer = center.addObserver(
                        forName: .EKEventStoreChanged,
                        object: nil,
                        queue: .main
                    ) { _ in
                        log.info("Calendar change notification received")
                        continuation.yield()
                    }
                    continuation.onTermination = { _ in
                        center.removeObserver(observer)
                    }
                }
            },
            fetchDayContent: { date in
                await _fetchDayContent(
                    for: date,
                    eventKit: eventKit,
                    cal: calendarContext
                )
            },
            generateForDay: { date in
                // V1: per-date FM generation isn't built yet. For today,
                // delegate through the same single-flight path as
                // `fetchOrGenerate` so wheel-dismiss + .appeared races
                // collapse to one insert. For other dates, return
                // any cached record or throw — the reducer treats throw
                // as "no brief available."
                let dayKey = calendarContext.dayKey(date)
                let todayKey = calendarContext.dayKey(calendarContext.now())
                if dayKey == todayKey {
                    let task = inflight.withValue { dict -> Task<DailyBriefSnapshot, any Error> in
                        if let existing = dict[todayKey] {
                            log.info("generateForDay(today): joining in-flight for \(todayKey)")
                            return existing
                        }
                        let newTask = Task<DailyBriefSnapshot, any Error> {
                            defer { inflight.withValue { $0[todayKey] = nil } }
                            return try await _fetchOrGenerate(
                                modelContext: modelContext,
                                eventKit: eventKit,
                                foundationModels: foundationModels,
                                cal: calendarContext
                            )
                        }
                        dict[todayKey] = newTask
                        return newTask
                    }
                    return try await task.value
                }
                // Cached past-day record if it exists.
                if let existing = await _fetch(forDayKey: dayKey, modelContext: modelContext, cal: calendarContext) {
                    return existing
                }
                // No record + not today — V1 has no per-date FM path.
                // Throwing here is honest: the reducer will leave the
                // brief in its prior state rather than fabricate one.
                throw NSError(
                    domain: "DailyBriefClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Per-date brief generation not yet implemented."]
                )
            }
        )
    }
}

// MARK: - DayContent fetcher

/// Fast, FM-free per-date fetch of events + reminders. Used by the Time
/// Warp wheel to populate the Calendar / Reminders tabs as the user
/// scrubs. No SwiftData reads, no Foundation Models — just EventKit.
///
private func _fetchDayContent(
    for date: Date,
    eventKit: EventKitService,
    cal: CalendarContext
) async -> DayContent {
    let dayKey = cal.dayKey(date)

    // Always live EventKit, any day. Reasons:
    //   - Freshness — cached highlights are frozen at brief-generation
    //     time, so anything added later doesn't appear if we read from
    //     the record.
    //   - Schema resilience — the cached `highlightsData` JSON depends
    //     on the `StoredHighlight` shape; future schema changes break
    //     stored records silently. Live EventKit is schema-independent.
    //   - Uniformity — the wheel can scrub to any day and the tab body
    //     populates the same way for past, today, and future. The
    //     cached `DailyBriefRecord` keeps its narrower job: persisting
    //     the FM-generated editorial text (focus / suggestion), not
    //     the events list.
    let events = (try? await eventKit.fetchEvents(date)) ?? []
    let reminders = (try? await eventKit.fetchReminders(date)) ?? []
    let highlights = buildHighlights(
        events: events,
        reminders: reminders,
        viewingDate: date,
        now: cal.now(),
        cal: cal
    )
    let eventRows = highlights.filter {
        $0.category == .allDay || $0.category == .upcoming
    }
    let reminderRows = highlights.filter {
        $0.category == .anytime || $0.category == .overdue || $0.category == .today
    }
    // Counts mirror the rendered list — `buildHighlights` is the source
    // of truth for "what the user sees." Using the raw EventKit counts
    // here drifts from the list whenever an event is excluded for any
    // reason (e.g., declined, canceled in future slices).
    return DayContent(
        dayKey: dayKey,
        events: eventRows,
        reminders: reminderRows,
        eventCount: eventRows.count,
        reminderCount: reminderRows.count,
        birthdayCount: 0
    )
}

// MARK: - Live implementation

@MainActor
private func _fetchOrGenerate(
    modelContext: SyncedModelContextDependency,
    eventKit: EventKitService,
    foundationModels: FoundationModelsService,
    cal: CalendarContext
) async throws -> DailyBriefSnapshot {
    let context = modelContext.context()
    let now = cal.now()
    let todayKey = cal.dayKey(now)
    log.info("fetchOrGenerate: dayKey=\(todayKey)")

    // Permission short-circuit. When neither calendar nor reminders is
    // authorized there's nothing to generate from. Skipping here avoids
    // (a) hitting FM with empty data (which hallucinates), and (b)
    // thrashing the cache predicate on every call (which would force
    // an "empty cached + FM available = regenerate" loop). If there's
    // a previously-cached record (possibly with hallucinated content
    // from before this fix or from a prior permissions-granted state),
    // we wipe its content to empty so the view hides cleanly — the
    // brief view shows nothing on empty focus.
    let canFetchEvents = eventKit.eventAuthStatus() == .fullAccess
    let canFetchReminders = eventKit.reminderAuthStatus() == .fullAccess
    if !canFetchEvents && !canFetchReminders {
        log.info("fetchOrGenerate: neither calendar nor reminders authorized — short-circuit")
        if let existing = try? loadRecord(forDayKey: todayKey, context: context) {
            if !existing.focusText.isEmpty || !existing.suggestionText.isEmpty {
                existing.focusText = ""
                existing.suggestionText = ""
                existing.eventCountAtGeneration = 0
                existing.reminderCountAtGeneration = 0
                try? context.save()
            }
            return DailyBriefSnapshot(record: existing, wasPersisted: true)
        }
        // No cached record — runGeneration's gate returns empty, so
        // generateNew persists an empty record. Subsequent calls take
        // the cached-record branch above and don't re-enter generation.
        return try await generateNew(
            dayKey: todayKey,
            now: now,
            eventCount: 0,
            reminderCount: 0,
            context: context,
            eventKit: eventKit,
            foundationModels: foundationModels,
            cal: cal
        )
    }

    do {
        if let existing = try loadRecord(forDayKey: todayKey, context: context) {
            log.info("fetchOrGenerate: found cached — events=\(existing.eventCountAtGeneration), reminders=\(existing.reminderCountAtGeneration), focusEmpty=\(existing.focusText.isEmpty)")

            let counts = await fetchLiveCounts(eventKit: eventKit)

            // Cache-hit predicate. A cached record is returned only when
            // ALL of these hold:
            //   (a) counts match — staleness check.
            //   (b) EventKit succeeded — (0,0) from a failed query is not
            //       a reliable baseline; the cached (0,0) record could
            //       persist forever during a permission-denied state.
            //   (c) the record has real content OR FM is currently
            //       unable to produce content. An empty-content record
            //       (focusText="" + suggestionText="") generated during
            //       a transient FM failure poisons the cache otherwise —
            //       every fetch would short-circuit and the view would
            //       hide the brief permanently. If FM is back, fall
            //       through to regenerate; if it's still unavailable,
            //       return the empty cache to avoid thrashing.
            let countsMatch = existing.eventCountAtGeneration == counts.eventCount
                && existing.reminderCountAtGeneration == counts.reminderCount
            let isEmptyContent = existing.focusText.isEmpty && existing.suggestionText.isEmpty
            let fmCanRegenerate = foundationModels.isAvailable()
                && foundationModels.supportsLocale(cal.userLocale())

            if countsMatch && counts.eventKitOK && !(isEmptyContent && fmCanRegenerate) {
                log.info("fetchOrGenerate: counts match — returning cached")
                DailyBriefRetention.touchIfStale(existing, now: now, context: context)
                // Loaded from SwiftData — it's persisted by definition.
                return DailyBriefSnapshot(record: existing, wasPersisted: true)
            }

            if isEmptyContent && fmCanRegenerate {
                log.info("fetchOrGenerate: empty cached + FM available — regenerating")
            } else if !counts.eventKitOK && countsMatch {
                log.info("fetchOrGenerate: counts (0,0) but EventKit failed — regenerating")
            } else {
                log.info("fetchOrGenerate: counts differ — regenerating")
            }
            return try await regenerate(
                existing: existing,
                eventCount: counts.eventCount,
                reminderCount: counts.reminderCount,
                context: context,
                eventKit: eventKit,
                foundationModels: foundationModels,
                cal: cal
            )
        }
    } catch {
        log.error("fetchOrGenerate: SwiftData query failed — \(error)")
    }

    log.info("fetchOrGenerate: no cached record — generating new")
    let counts = await fetchLiveCounts(eventKit: eventKit)

    return try await generateNew(
        dayKey: todayKey,
        now: now,
        eventCount: counts.eventCount,
        reminderCount: counts.reminderCount,
        context: context,
        eventKit: eventKit,
        foundationModels: foundationModels,
        cal: cal
    )
}

@MainActor
private func _refresh(
    modelContext: SyncedModelContextDependency,
    eventKit: EventKitService,
    foundationModels: FoundationModelsService,
    cal: CalendarContext
) async throws -> DailyBriefSnapshot {
    let context = modelContext.context()
    let now = cal.now()
    let todayKey = cal.dayKey(now)
    let counts = await fetchLiveCounts(eventKit: eventKit)
    log.info("refresh: force regenerating for \(todayKey)")

    if let existing = try loadRecord(forDayKey: todayKey, context: context) {
        return try await regenerate(
            existing: existing,
            eventCount: counts.eventCount,
            reminderCount: counts.reminderCount,
            context: context,
            eventKit: eventKit,
            foundationModels: foundationModels,
            cal: cal
        )
    }

    return try await generateNew(
        dayKey: todayKey,
        now: now,
        eventCount: counts.eventCount,
        reminderCount: counts.reminderCount,
        context: context,
        eventKit: eventKit,
        foundationModels: foundationModels,
        cal: cal
    )
}

// MARK: - Read-only fetch

@MainActor
private func _fetch(
    forDayKey dayKey: String,
    modelContext: SyncedModelContextDependency,
    cal: CalendarContext
) -> DailyBriefSnapshot? {
    let context = modelContext.context()
    guard let record = try? loadRecord(forDayKey: dayKey, context: context) else {
        return nil
    }
    DailyBriefRetention.touchIfStale(record, now: cal.now(), context: context)
    // Loaded from SwiftData — it's persisted by definition.
    return DailyBriefSnapshot(record: record, wasPersisted: true)
}

// MARK: - SwiftData operations

@MainActor
private func loadRecord(forDayKey dayKey: String, context: ModelContext) throws -> DailyBriefRecord? {
    let descriptor = FetchDescriptor<DailyBriefRecord>(
        predicate: #Predicate { $0.dayKey == dayKey }
    )
    let results = try context.fetch(descriptor)
    return results.first
}

// Retention helpers (`touchIfStale`, `evictIfNeeded`) live in
// `DailyBriefRetention.swift` so they can be tested directly against an
// in-memory `ModelContainer`.

@MainActor
private func generateNew(
    dayKey: String,
    now: Date,
    eventCount: Int,
    reminderCount: Int,
    context: ModelContext,
    eventKit: EventKitService,
    foundationModels: FoundationModelsService,
    cal: CalendarContext
) async throws -> DailyBriefSnapshot {
    let (focusText, suggestionText) = try await runGeneration(
        eventKit: eventKit,
        foundationModels: foundationModels,
        cal: cal
    )

    let record = DailyBriefRecord(
        dayKey: dayKey,
        focusText: focusText,
        suggestionText: suggestionText,
        eventCountAtGeneration: eventCount,
        reminderCountAtGeneration: reminderCount,
        generatedAt: now
    )

    context.insert(record)
    var wasPersisted = true
    do {
        try context.save()
        log.info("generateNew: persisted to SwiftData")
        // Eviction runs immediately after a successful insert. This is
        // the only growth path for the record set, so this single
        // trigger point keeps the LRU bounded without scheduling a
        // separate cleanup job.
        DailyBriefRetention.evictIfNeeded(context: context)
    } catch {
        wasPersisted = false
        // Fault-level: SwiftData save failure is rare and almost always
        // load-bearing (disk full, iCloud conflict, schema mismatch).
        // We continue to return the in-memory snapshot so the user
        // sees today's brief, but flag wasPersisted=false so callers
        // can surface a hint and so we don't loop on subsequent calls.
        log.fault("generateNew: SwiftData save failed — \(error, privacy: .public)")
    }

    return DailyBriefSnapshot(record: record, wasPersisted: wasPersisted)
}

@MainActor
private func regenerate(
    existing: DailyBriefRecord,
    eventCount: Int,
    reminderCount: Int,
    context: ModelContext,
    eventKit: EventKitService,
    foundationModels: FoundationModelsService,
    cal: CalendarContext
) async throws -> DailyBriefSnapshot {
    let (focusText, suggestionText) = try await runGeneration(
        eventKit: eventKit,
        foundationModels: foundationModels,
        cal: cal
    )

    let now = cal.now()
    existing.focusText = focusText
    existing.suggestionText = suggestionText
    existing.eventCountAtGeneration = eventCount
    existing.reminderCountAtGeneration = reminderCount
    existing.generatedAt = now
    // Regen counts as access — the user just triggered it.
    existing.lastAccessedAt = now

    var wasPersisted = true
    do {
        try context.save()
        log.info("regenerate: persisted to SwiftData")
    } catch {
        wasPersisted = false
        log.fault("regenerate: SwiftData save failed — \(error, privacy: .public)")
    }

    return DailyBriefSnapshot(record: existing, wasPersisted: wasPersisted)
}

// MARK: - Generation core

private func runGeneration(
    eventKit: EventKitService,
    foundationModels: FoundationModelsService,
    cal: CalendarContext
) async throws -> (
    focusText: String,
    suggestionText: String
) {
    // Permission gate (must come before fetching). `EventKitService`
    // returns `[]` from `fetchTodayEvents` / `fetchDueReminders` when
    // authorization is not `.fullAccess` — which is indistinguishable
    // from a real empty day at the call site. Passing that data to
    // Foundation Models causes the model to hallucinate plausible-
    // sounding placeholder items ("meeting with client A", "report
    // due") to fill the gap rather than write about nothing.
    //
    // Each source is gated independently so a user who granted
    // calendar but not reminders still gets a calendar-only brief,
    // and vice versa. Only when BOTH are denied do we skip the FM
    // call entirely — the view already hides the editor's note on
    // empty focus, so this routes the denied state to that path.
    let canFetchEvents = eventKit.eventAuthStatus() == .fullAccess
    let canFetchReminders = eventKit.reminderAuthStatus() == .fullAccess

    guard canFetchEvents || canFetchReminders else {
        log.info("runGeneration: neither calendar nor reminders authorized — skipping FM, brief hidden")
        return ("", "")
    }

    log.info("runGeneration: fetching EventKit (events=\(canFetchEvents), reminders=\(canFetchReminders))")
    let events = canFetchEvents ? (try await eventKit.fetchTodayEvents()) : []
    let reminders = canFetchReminders ? (try await eventKit.fetchDueReminders()) : []
    log.info("runGeneration: EventKit — \(events.count) events, \(reminders.count) reminders")

    var focusText = ""
    var suggestionText = ""

    // FM is usable for this user when (a) the framework is available
    // on this device and (b) it can produce output in the user's
    // locale. Per Apple's docs the framework does NOT auto-fallback
    // across locales — asking for unsupported output yields English
    // or garbled text. Gating on both is the documented pattern.
    //
    // When either gate fails (or FM retries exhaust), focusText and
    // suggestionText stay empty. The view hides the editor's note
    // section entirely on empty content. The tabs continue to show
    // events / reminders / birthdays directly — the brief is
    // editorial commentary on data the user already sees, so its
    // absence is graceful, not a degradation.
    //
    // Hand-written fallback prose was deliberately removed (see
    // `localization_edd.md §5`): synthesizing the brief in code
    // would require maintaining N-language translations of mechanical
    // sentences that restate the same data the tabs already show.
    // Hide-rather-than-fake is the cleaner contract.
    let fmAvailable = foundationModels.isAvailable()
    let localeSupported = foundationModels.supportsLocale(cal.userLocale())

    guard fmAvailable && localeSupported else {
        if !localeSupported {
            log.info("runGeneration: locale \(cal.userLocale().identifier) not supported by FM — brief hidden")
        } else {
            log.info("runGeneration: FM unavailable on this device — brief hidden")
        }
        return (focusText, suggestionText)
    }

    let prompt = buildPrompt(
        events: events,
        reminders: reminders,
        includeCalendarSection: canFetchEvents,
        includeRemindersSection: canFetchReminders,
        cal: cal
    )
    if let brief = await runFMWithRetry(prompt: prompt, foundationModels: foundationModels) {
        focusText = brief.focus
        suggestionText = brief.suggestion
    } else {
        log.info("runGeneration: FM retries exhausted — brief hidden")
    }

    return (focusText, suggestionText)
}

/// Runs FM generation with bounded retry on transient failures.
///
/// On-device Foundation Models occasionally surface ANE inference
/// errors (`Code=8 ... Program Inference error`) that are recoverable
/// within a few hundred milliseconds — typically the ANE was busy
/// finishing another model's work. One retry rescues the vast
/// majority; we cap at two attempts so we don't stretch the perceived
/// brief-generation latency beyond a few seconds.
///
/// Returns nil when both attempts fail. Caller falls back to the
/// non-FM prose generator.
private func runFMWithRetry(
    prompt: String,
    foundationModels: FoundationModelsService,
    maxAttempts: Int = 2
) async -> (focus: String, suggestion: String)? {
    for attempt in 1...maxAttempts {
        do {
            let brief = try await foundationModels.generateBrief(prompt)
            return (brief.focus, brief.suggestion)
        } catch {
            log.warning("FM attempt \(attempt)/\(maxAttempts) failed — \(error)")
            // Backoff before retry; skip on the final attempt.
            if attempt < maxAttempts {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
    return nil
}

/// Resolves the English name of a locale's language (e.g., "French",
/// "Japanese", "Simplified Chinese"). Used in the FM prompt's
/// language directive — English names are the most reliable form for
/// the model's cross-lingual instruction-following.
///
/// Includes script when present (Chinese Simplified vs Traditional)
/// since they're distinct enough to matter for fluent output. Falls
/// back to the raw language code if no localized name is available
/// — the model will usually still cope.
private func englishLanguageName(for locale: Locale) -> String {
    let language = locale.language
    var tag = language.languageCode?.identifier ?? "en"
    if let script = language.script?.identifier {
        tag += "-\(script)"
    }
    return Locale(identifier: "en_US").localizedString(forLanguageCode: tag)
        ?? language.languageCode?.identifier
        ?? "English"
}

/// Live counts of today's events + reminders. `eventKitOK` is false if
/// either fetch threw — in that state, a cached record with counts
/// (0, 0) is NOT a reliable match (could be a real empty day, could be
/// a permission denial). Callers must check `eventKitOK` before
/// treating a (0, 0) match as cache-fresh.
private func fetchLiveCounts(
    eventKit: EventKitService
) async -> (eventCount: Int, reminderCount: Int, eventKitOK: Bool) {
    do {
        let events = try await eventKit.fetchTodayEvents()
        let reminders = try await eventKit.fetchDueReminders()
        return (events.count, reminders.count, true)
    } catch {
        log.error("fetchLiveCounts: failed — \(error)")
        return (0, 0, false)
    }
}

// MARK: - Highlight builder

/// Builds the rendered highlight rows for `viewingDate`. The list is the
/// source of truth for what the user sees in the Calendar / Reminders
/// tabs — counts come from this list's size, not from a parallel raw
/// EventKit count.
///
/// Ordering:
///   1. All-day events (pinned, sorted as EventKit returned them).
///   2. All timed events for the day, sorted chronologically. No filter
///      on past-vs-future — a passed event is still part of the day.
///   3. Anytime / undated reminders.
///   4. All timed reminders, sorted chronologically.
///
/// `.overdue` semantics (reminders):
///   - Only applies when `viewingDate` is today. On past/future days,
///     "overdue" is meaningless — those reminders are just `.today`.
///
private func buildHighlights(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot],
    viewingDate: Date,
    now: Date,
    cal: CalendarContext
) -> [StoredHighlight] {
    var highlights: [StoredHighlight] = []
    let isToday = cal.isToday(viewingDate)

    // Events
    let allDayEvents = events.filter { $0.isAllDay }
    let timedEvents = events
        .filter { !$0.isAllDay }
        .sorted { $0.startDate < $1.startDate }

    // The "next up" pill was dropped in favor of a per-row
    // in-progress indicator. The in-progress check is a UI concern
    // computed at the adapter from `startDate`/`endDate` (carried
    // below) against the adapter's clock reference — no event-to-
    // event coupling here, no derived state on the transport.

    for event in allDayEvents {
        highlights.append(
            StoredHighlight(
                category: .allDay,
                icon: "calendar",
                title: event.title,
                time: AppStrings.Home.allDay,
                trailingBadge: "",
                sourceNotebookID: nil,
                sourcePageIndex: nil,
                // All-day events have no clock-time semantics —
                // omit start/end so the adapter's in-progress
                // predicate naturally falls through to false.
                startDate: nil,
                endDate: nil
            )
        )
    }
    for event in timedEvents {
        highlights.append(
            StoredHighlight(
                category: .upcoming,
                icon: "calendar",
                title: event.title,
                time: event.startDate.formatted(.dateTime.hour().minute()),
                // Trailing badge is derived at the adapter (against
                // `state.nowTick`) so it stays in sync with the
                // in-progress predicate AND advances cleanly across
                // event start/end transitions. Storing a stale string
                // here would only get overwritten on every adapter
                // render anyway.
                trailingBadge: "",
                sourceNotebookID: nil,
                sourcePageIndex: nil,
                startDate: event.startDate,
                endDate: event.endDate
            )
        )
    }

    // Reminders
    let anytimeReminders = reminders.filter { $0.isAllDay }
    let timedReminders = reminders
        .filter { !$0.isAllDay }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

    for reminder in anytimeReminders {
        highlights.append(
            StoredHighlight(
                category: .anytime,
                icon: "clock",
                title: reminder.title,
                time: AppStrings.Home.anytime,
                trailingBadge: "",
                sourceNotebookID: nil,
                sourcePageIndex: nil,
                startDate: nil,
                endDate: nil
            )
        )
    }
    for reminder in timedReminders {
        let category: HighlightCategory = {
            guard isToday, let due = reminder.dueDate else { return .today }
            return due < now ? .overdue : .today
        }()
        highlights.append(
            StoredHighlight(
                category: category,
                icon: "clock",
                title: reminder.title,
                time: reminder.dueDate?.formatted(.dateTime.hour().minute()) ?? "",
                trailingBadge: reminder.dueDate.map { reminderBadge($0, now: now) } ?? "",
                sourceNotebookID: nil,
                sourcePageIndex: nil,
                // Reminders don't have a duration — no in-progress
                // semantics. `.overdue` is encoded in the category.
                startDate: nil,
                endDate: nil
            )
        )
    }

    return highlights
}

private func reminderBadge(_ dueDate: Date, now: Date) -> String {
    let minutes = Int(dueDate.timeIntervalSince(now) / 60)
    if minutes <= 0 { return AppStrings.Home.overdue }
    if minutes < 60 { return "In \(minutes) m" }
    let hours = minutes / 60
    if hours < 24 { return "In \(hours) h" }
    return "In \(hours / 24) d"
}

// MARK: - Prompt builder

/// Builds the FM prompt. Goal: a short, human daily note that feels
/// like the app knows the user from their actual calendar and
/// reminders. Structure is three parts:
///
///   1. Optional language directive (non-English locales only).
///   2. Setup + data (today's date and whatever sections the user
///      has authorized).
///   3. A single closing instruction with the format, voice, and
///      no-invention rule.
///
/// Sections are omitted entirely when the user hasn't granted that
/// source — denied data is not represented in the prompt at all so
/// the model doesn't confuse "no permission" with "real empty day."
private func buildPrompt(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot],
    includeCalendarSection: Bool,
    includeRemindersSection: Bool,
    cal: CalendarContext
) -> String {
    let now = cal.now()
    let todayFormatted = now.formatted(
        .dateTime.weekday(.wide).month(.wide).day().year()
            .locale(cal.userLocale())
    )
    var parts: [String] = []

    // Language directive — placed first (primacy effect) so the model
    // locks onto the target output language before reading the English
    // instruction body. Skipped for English locales since telling an
    // English-locale model to "respond in English" when the prompt is
    // already in English just adds noise. Language name is rendered
    // in English (e.g., "French", "Japanese") — most reliable form
    // for the model's instruction-following.
    let langCode = cal.userLocale().language.languageCode?.identifier ?? "en"
    if langCode != "en" {
        let name = englishLanguageName(for: cal.userLocale())
        parts.append("Respond ONLY in \(name). Even though these instructions are in English, your entire output must be in \(name).")
    }

    parts.append("You're writing a short personal daily note for the user, grounded in their real calendar and reminders. Today is \(todayFormatted).")

    if includeCalendarSection {
        if events.isEmpty {
            parts.append("Calendar today: nothing scheduled.")
        } else {
            let list = events.map {
                "- \($0.startDate.formatted(.dateTime.hour().minute())): \($0.title)"
            }.joined(separator: "\n")
            parts.append("Calendar today:\n\(list)")
        }
    }
    if includeRemindersSection {
        if reminders.isEmpty {
            parts.append("Reminders due: none.")
        } else {
            let list = reminders.prefix(5).map { "- \($0.title)" }.joined(separator: "\n")
            parts.append("Reminders due:\n\(list)")
        }
    }

    parts.append("""
    Write the 'focus' as 2–3 sentences in second person ("you", "your"), addressed to the user. Reference real events by title (and time) and real reminders by name. Never invent items that aren't listed above; if nothing is listed, the focus must be an empty string. Speak naturally — like a thoughtful assistant who knows what's on the user's plate today.

    Write the 'suggestion' as one short, specific tip drawn directly from the listed items, or an empty string if nothing specific applies.
    """)

    return parts.joined(separator: "\n\n")
}

// `rawFocusFallback` was deliberately removed (commit history).
//
// The function used to synthesize a deterministic prose brief from
// events + reminders when Foundation Models was unavailable. It
// required N-language localized chrome strings to be authored and
// translated; the resulting prose mechanically restated information
// the user already sees in the Calendar / Reminders / Birthdays
// tabs.
//
// The new contract: when FM cannot generate a brief, the editor's
// note section hides entirely (HomeDailyBrief checks for empty
// focusText). The tabs continue to render — they are the truth.
// See `localization_edd.md §5`.
