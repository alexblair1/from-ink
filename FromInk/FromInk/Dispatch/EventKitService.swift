import Foundation
import EventKit
import Dependencies

// MARK: - Snapshot types (Sendable, decoupled from EK reference types)

struct CalendarEventSnapshot: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    /// True if the event is marked all-day (`EKEvent.isAllDay`). All-day
    /// events get separate UX treatment — pinned to the top of the day's
    /// list and ineligible for the "next up" slot.
    let isAllDay: Bool
}

struct ReminderSnapshot: Sendable, Equatable {
    let title: String
    let dueDate: Date?
    /// True if the reminder has no specific time of day — either no due
    /// date at all (`dueDateComponents == nil`) or a due date with no
    /// `hour` component. Matches Apple's "Today, anytime" semantics.
    let isAllDay: Bool
}

// MARK: - Dependency

struct EventKitService: Sendable {
    var fetchTodayEvents: @Sendable () async throws -> [CalendarEventSnapshot]
    var fetchDueReminders: @Sendable () async throws -> [ReminderSnapshot]

    /// Events whose start time falls within the user-local day containing
    /// `date`. Used by the Time Warp wheel to populate the Calendar tab
    /// for any scrubbed-to day, not just today.
    var fetchEvents: @Sendable (Date) async throws -> [CalendarEventSnapshot]

    /// Incomplete reminders with a due date inside the user-local day
    /// containing `date`. Distinct from `fetchDueReminders`, which is
    /// brief-generation semantics (all overdue + due-today regardless of
    /// the day being viewed).
    var fetchReminders: @Sendable (Date) async throws -> [ReminderSnapshot]

    // MARK: - Authorization

    /// Synchronous read of the current calendar event authorization.
    /// Used by the Permissions settings surface to render row state and
    /// by call-site guards (we already check this inside `fetchEvents`).
    var eventAuthStatus: @Sendable () -> PermissionAuthStatus
    /// Synchronous read of the current reminder authorization.
    var reminderAuthStatus: @Sendable () -> PermissionAuthStatus

    /// Prompts the user for full calendar access via the iOS 17+ API.
    /// Resolves to the post-prompt status (which may still be `.denied`
    /// if the user declined). Idempotent: if access is already granted,
    /// returns immediately without re-prompting.
    var requestEventAccess: @Sendable () async -> PermissionAuthStatus
    /// Prompts the user for full reminder access.
    var requestReminderAccess: @Sendable () async -> PermissionAuthStatus
}

extension EventKitService: DependencyKey {
    static var liveValue: Self {
        let store = EKEventStore()

        @Sendable func eventSnapshots(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
            // Discard EKEventStore's in-memory cache before each query.
            //
            // EKEventStoreChanged tells our process "the database changed,"
            // but our long-lived EKEventStore instance still holds cached
            // EKEvent objects from before the change. Calling `events(matching:)`
            // without first calling `reset()` returns those stale objects —
            // visible to the user as "the brief regenerated but missed the
            // event I just added." Apple's documented fix is `reset()`,
            // which releases the in-memory cache so the next query reads
            // fresh from the database. Cost is microseconds; the date
            // predicate query is already a fresh disk read.
            store.reset()
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: pred)
                .sorted { $0.startDate < $1.startDate }
                .map {
                    CalendarEventSnapshot(
                        title: $0.title ?? "",
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        calendarTitle: $0.calendar?.title ?? "",
                        isAllDay: $0.isAllDay
                    )
                }
        }

        @Sendable func reminderSnapshots(
            withDueDateStarting start: Date?,
            ending end: Date
        ) async throws -> [ReminderSnapshot] {
            // See eventSnapshots: discard the in-memory cache so each
            // query reflects the current database state. Reminders share
            // the same EKEventStore instance, so they're equally subject
            // to staleness without an explicit reset.
            store.reset()
            return try await withCheckedThrowingContinuation { continuation in
                let pred = store.predicateForIncompleteReminders(
                    withDueDateStarting: start,
                    ending: end,
                    calendars: nil
                )
                store.fetchReminders(matching: pred) { reminders in
                    let snapshots = (reminders ?? [])
                        .sorted {
                            ($0.dueDateComponents?.date ?? .distantFuture) <
                            ($1.dueDateComponents?.date ?? .distantFuture)
                        }
                        .map { reminder -> ReminderSnapshot in
                            // "All day" = no due date at all, OR a due
                            // date with no time component. Matches what
                            // Apple's Reminders.app lumps into the
                            // "Today (anytime)" group.
                            let components = reminder.dueDateComponents
                            let isAllDay = components == nil || components?.hour == nil
                            return ReminderSnapshot(
                                title: reminder.title ?? "",
                                dueDate: components?.date,
                                isAllDay: isAllDay
                            )
                        }
                    continuation.resume(returning: snapshots)
                }
            }
        }

        // Resolves the user-local [startOfDay, startOfNextDay) range for
        // any input date. Uses `Calendar.autoupdatingCurrent` to follow
        // locale + timezone changes without app restart — the dates EDD's
        // intent is "always interpret day boundaries in the user's
        // current calendar." A future cleanup will inject CalendarContext
        // into this client; for now we match the existing pattern at the
        // top of this file.
        @Sendable func dayRange(for date: Date) -> (start: Date, end: Date) {
            let cal = Calendar.autoupdatingCurrent
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return (start, end)
        }

        @Sendable func eventStatus() -> PermissionAuthStatus {
            PermissionAuthStatus(EKEventStore.authorizationStatus(for: .event))
        }
        @Sendable func reminderStatus() -> PermissionAuthStatus {
            PermissionAuthStatus(EKEventStore.authorizationStatus(for: .reminder))
        }

        return .init(
            fetchTodayEvents: {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                    return []
                }
                let (start, end) = dayRange(for: Date())
                return eventSnapshots(from: start, to: end)
            },
            fetchDueReminders: {
                guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                    return []
                }
                let (_, end) = dayRange(for: Date())
                return try await reminderSnapshots(withDueDateStarting: nil, ending: end)
            },
            fetchEvents: { date in
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                    return []
                }
                let (start, end) = dayRange(for: date)
                return eventSnapshots(from: start, to: end)
            },
            fetchReminders: { date in
                guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                    return []
                }
                // Two semantics depending on whether `date` is today:
                //
                // - Today: use the broad predicate (nil start, end-of-day).
                //   This matches what Apple's Reminders.app "Today" smart
                //   list shows — incomplete reminders due any time up to
                //   end-of-day PLUS reminders with no due date at all.
                //   Excluding undated reminders here would silently hide
                //   anything the user added to "Today" without a time.
                //
                // - Other day: use the strict day range (start-of-day,
                //   end-of-day). Only reminders explicitly scheduled for
                //   that day appear. Overdue + undated reminders are not
                //   conceptually "for" a past or future day, so they're
                //   excluded.
                let (start, end) = dayRange(for: date)
                let today = Calendar.autoupdatingCurrent.isDateInToday(date)
                return try await reminderSnapshots(
                    withDueDateStarting: today ? nil : start,
                    ending: end
                )
            },
            eventAuthStatus: { eventStatus() },
            reminderAuthStatus: { reminderStatus() },
            requestEventAccess: {
                // Idempotent — if already granted, skip the prompt so
                // we don't surface a system dialog the user has already
                // resolved.
                if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
                    return .fullAccess
                }
                _ = try? await store.requestFullAccessToEvents()
                return eventStatus()
            },
            requestReminderAccess: {
                if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
                    return .fullAccess
                }
                _ = try? await store.requestFullAccessToReminders()
                return reminderStatus()
            }
        )
    }

    static var testValue: Self {
        let canned = CalendarEventSnapshot(
            title: "Product Review",
            startDate: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!,
            endDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!,
            calendarTitle: "Work",
            isAllDay: false
        )
        let cannedReminder = ReminderSnapshot(
            title: "Follow up with Sarah",
            dueDate: Date(),
            isAllDay: false
        )

        return .init(
            fetchTodayEvents: { [canned] },
            fetchDueReminders: { [cannedReminder] },
            fetchEvents: { _ in [canned] },
            fetchReminders: { _ in [cannedReminder] },
            eventAuthStatus: { .fullAccess },
            reminderAuthStatus: { .fullAccess },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .fullAccess }
        )
    }
}

extension DependencyValues {
    var eventKitService: EventKitService {
        get { self[EventKitService.self] }
        set { self[EventKitService.self] = newValue }
    }
}
