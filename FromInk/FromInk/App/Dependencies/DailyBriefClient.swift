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
}

// MARK: - DependencyKey

extension DailyBriefClient: DependencyKey {
    /// Minimal fallback — not a functioning implementation.
    /// The real live client is built via .live() factory in AppDependencyContainer.
    static let liveValue = DailyBriefClient(
        fetchOrGenerate: { throw CancellationError() },
        refresh: { throw CancellationError() },
        fetch: { _ in nil },
        calendarChanges: { AsyncStream { $0.finish() } }
    )

    static let testValue = DailyBriefClient(
        fetchOrGenerate: { throw CancellationError() },
        refresh: { throw CancellationError() },
        fetch: { _ in nil },
        calendarChanges: { AsyncStream { $0.finish() } }
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
                await _fetch(forDayKey: dayKey, modelContext: modelContext)
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
            }
        )
    }
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
    modelContext: SyncedModelContextDependency
) -> DailyBriefSnapshot? {
    let context = modelContext.context()
    guard let record = try? loadRecord(forDayKey: dayKey, context: context) else {
        return nil
    }
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
    let (focusText, suggestionText, highlights) = try await runGeneration(
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
        generatedAt: now,
        highlights: highlights
    )

    context.insert(record)
    do {
        try context.save()
        log.info("generateNew: persisted to SwiftData")
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
    let (focusText, suggestionText, highlights) = try await runGeneration(
        eventKit: eventKit,
        foundationModels: foundationModels,
        cal: cal
    )

    existing.focusText = focusText
    existing.suggestionText = suggestionText
    existing.eventCountAtGeneration = eventCount
    existing.reminderCountAtGeneration = reminderCount
    existing.generatedAt = cal.now()
    existing.setHighlights(highlights)

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
    suggestionText: String,
    highlights: [StoredHighlight]
) {
    log.info("runGeneration: fetching EventKit")
    let events = try await eventKit.fetchTodayEvents()
    let reminders = try await eventKit.fetchDueReminders()
    log.info("runGeneration: EventKit — \(events.count) events, \(reminders.count) reminders")

    let now = cal.now()
    let highlights = buildHighlights(events: events, reminders: reminders, now: now, cal: cal)

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

    return (focusText, suggestionText, highlights)
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

private func buildHighlights(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot],
    now: Date,
    cal: CalendarContext
) -> [StoredHighlight] {
    var highlights: [StoredHighlight] = []

    let upcoming = events.filter { $0.startDate >= now || $0.endDate >= now }
    for (index, event) in upcoming.prefix(3).enumerated() {
        let category = index == 0 ? AppStrings.Home.nextUp : AppStrings.Home.upcoming
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

    for reminder in reminders.prefix(3) {
        let category = reminder.dueDate.map {
            $0 < now ? AppStrings.Home.overdue : AppStrings.Home.today
        } ?? AppStrings.Home.today
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
