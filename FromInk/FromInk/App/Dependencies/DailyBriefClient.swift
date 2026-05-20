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
        DailyBriefClient(
            fetchOrGenerate: {
                try await _fetchOrGenerate(
                    modelContext: modelContext,
                    eventKit: eventKit,
                    foundationModels: foundationModels,
                    cal: calendarContext
                )
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
                // delegate to fetchOrGenerate. For other dates, return
                // any cached record or throw — the reducer treats throw
                // as "no brief available."
                let dayKey = calendarContext.dayKey(date)
                let todayKey = calendarContext.dayKey(calendarContext.now())
                if dayKey == todayKey {
                    return try await _fetchOrGenerate(
                        modelContext: modelContext,
                        eventKit: eventKit,
                        foundationModels: foundationModels,
                        cal: calendarContext
                    )
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
        $0.category == .allDay || $0.category == .nextUp || $0.category == .upcoming
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

    do {
        if let existing = try loadRecord(forDayKey: todayKey, context: context) {
            log.info("fetchOrGenerate: found cached — events=\(existing.eventCountAtGeneration), reminders=\(existing.reminderCountAtGeneration)")

            let (eventCount, reminderCount) = await fetchLiveCounts(eventKit: eventKit)

            if existing.eventCountAtGeneration == eventCount
                && existing.reminderCountAtGeneration == reminderCount {
                log.info("fetchOrGenerate: counts match — returning cached")
                DailyBriefRetention.touchIfStale(existing, now: now, context: context)
                return DailyBriefSnapshot(record: existing)
            }

            log.info("fetchOrGenerate: counts differ — regenerating")
            return try await regenerate(
                existing: existing,
                eventCount: eventCount,
                reminderCount: reminderCount,
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
    let (eventCount, reminderCount) = await fetchLiveCounts(eventKit: eventKit)

    return try await generateNew(
        dayKey: todayKey,
        now: now,
        eventCount: eventCount,
        reminderCount: reminderCount,
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
    let (eventCount, reminderCount) = await fetchLiveCounts(eventKit: eventKit)
    log.info("refresh: force regenerating for \(todayKey)")

    if let existing = try loadRecord(forDayKey: todayKey, context: context) {
        return try await regenerate(
            existing: existing,
            eventCount: eventCount,
            reminderCount: reminderCount,
            context: context,
            eventKit: eventKit,
            foundationModels: foundationModels,
            cal: cal
        )
    }

    return try await generateNew(
        dayKey: todayKey,
        now: now,
        eventCount: eventCount,
        reminderCount: reminderCount,
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
    return DailyBriefSnapshot(record: record)
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
    do {
        try context.save()
        log.info("generateNew: persisted to SwiftData")
        // Eviction runs immediately after a successful insert. This is
        // the only growth path for the record set, so this single
        // trigger point keeps the LRU bounded without scheduling a
        // separate cleanup job.
        DailyBriefRetention.evictIfNeeded(context: context)
    } catch {
        log.error("generateNew: save failed — \(error)")
    }

    return DailyBriefSnapshot(record: record)
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

    do {
        try context.save()
        log.info("regenerate: persisted to SwiftData")
    } catch {
        log.error("regenerate: save failed — \(error)")
    }

    return DailyBriefSnapshot(record: existing)
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
    log.info("runGeneration: fetching EventKit")
    let events = try await eventKit.fetchTodayEvents()
    let reminders = try await eventKit.fetchDueReminders()
    log.info("runGeneration: EventKit — \(events.count) events, \(reminders.count) reminders")

    var focusText = ""
    var suggestionText = ""

    let fmAvailable = foundationModels.isAvailable()

    if fmAvailable {
        let prompt = buildPrompt(events: events, reminders: reminders, cal: cal)
        do {
            let brief = try await foundationModels.generateBrief(prompt)
            focusText = brief.focus
            suggestionText = brief.suggestion
        } catch {
            log.error("runGeneration: FM failed — \(error)")
            focusText = rawFocusFallback(events: events, reminders: reminders)
        }
    } else {
        focusText = rawFocusFallback(events: events, reminders: reminders)
    }

    return (focusText, suggestionText)
}

private func fetchLiveCounts(eventKit: EventKitService) async -> (Int, Int) {
    do {
        let events = try await eventKit.fetchTodayEvents()
        let reminders = try await eventKit.fetchDueReminders()
        return (events.count, reminders.count)
    } catch {
        log.error("fetchLiveCounts: failed — \(error)")
        return (0, 0)
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
/// `.nextUp` semantics:
///   - Only applies when `viewingDate` is today (the pill is anchored to
///     "right now," which doesn't exist on other days).
///   - The first timed event whose `endDate >= now` wins it; events
///     already ended are `.upcoming`. If no event is still ongoing or
///     future, no event gets `.nextUp`.
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

    // `.nextUp` is the first timed event with `endDate >= now` — only
    // when viewing today. nil index = no event wins the pill.
    let nextUpIndex: Int? = isToday
        ? timedEvents.firstIndex(where: { $0.endDate >= now })
        : nil

    for event in allDayEvents {
        highlights.append(
            StoredHighlight(
                category: .allDay,
                icon: "calendar",
                title: event.title,
                time: AppStrings.Home.allDay,
                trailingBadge: "",
                sourceNotebookID: nil,
                sourcePageIndex: nil
            )
        )
    }
    for (index, event) in timedEvents.enumerated() {
        let category: HighlightCategory = (index == nextUpIndex) ? .nextUp : .upcoming
        highlights.append(
            StoredHighlight(
                category: category,
                icon: "calendar",
                title: event.title,
                time: event.startDate.formatted(.dateTime.hour().minute()),
                trailingBadge: eventBadge(event, now: now, cal: cal),
                sourceNotebookID: nil,
                sourcePageIndex: nil
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
                sourcePageIndex: nil
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
                sourcePageIndex: nil
            )
        )
    }

    return highlights
}

private func eventBadge(
    _ event: CalendarEventSnapshot,
    now: Date,
    cal: CalendarContext
) -> String {
    let userCal = cal.userCalendar()
    let hours = userCal.dateComponents([.hour], from: event.startDate, to: event.endDate).hour ?? 0
    if cal.isSameDay(event.startDate, now) && hours >= 23 { return AppStrings.Home.allDay }
    let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
    if minutes <= 0 { return AppStrings.Home.now }
    if minutes < 60 { return "In \(minutes) m" }
    return "In \(minutes / 60) h"
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

private func buildPrompt(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot],
    cal: CalendarContext
) -> String {
    let now = cal.now()
    let todayFormatted = now.formatted(
        .dateTime.weekday(.wide).month(.wide).day().year()
            .locale(cal.userLocale())
    )
    var parts: [String] = [
        "Generate a concise daily brief. Today is \(todayFormatted)."
    ]
    if events.isEmpty {
        parts.append("Calendar: No events today.")
    } else {
        let list = events.map {
            "- \($0.startDate.formatted(.dateTime.hour().minute())): \($0.title)"
        }.joined(separator: "\n")
        parts.append("Calendar events:\n\(list)")
    }
    if !reminders.isEmpty {
        let list = reminders.prefix(5).map { "- \($0.title)" }.joined(separator: "\n")
        parts.append("Due reminders:\n\(list)")
    }
    parts.append(
        "Write 'focus' as a 2-3 sentence paragraph in plain English. "
        + "Name events by title and time, mention any overdue reminders "
        + "by name, and close with what matters most. No bullet points "
        + "or headers. Suggestion: one short actionable tip, or empty "
        + "string if nothing useful."
    )
    return parts.joined(separator: "\n\n")
}

private func rawFocusFallback(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot]
) -> String {
    guard !events.isEmpty || !reminders.isEmpty else {
        return AppStrings.Home.noEventsToday
    }
    var parts: [String] = []
    switch events.count {
    case 0:
        parts.append(AppStrings.Home.noEventsScheduled)
    case 1:
        let time = events[0].startDate.formatted(.dateTime.hour().minute())
        parts.append("You have \(events[0].title) at \(time) today.")
    default:
        let listed = events.prefix(3).map {
            "\($0.title) at \($0.startDate.formatted(.dateTime.hour().minute()))"
        }
        let tail = events.count > 3 ? " and \(events.count - 3) more" : ""
        parts.append("Today: \(listed.joined(separator: ", "))\(tail).")
    }
    if !reminders.isEmpty {
        let s = reminders.count == 1 ? "" : "s"
        parts.append("\(reminders.count) reminder\(s) due.")
    }
    return parts.joined(separator: " ")
}
