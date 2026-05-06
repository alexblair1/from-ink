import Foundation
import EventKit
import Dependencies

// MARK: - Snapshot types (Sendable, decoupled from EK reference types)

struct CalendarEventSnapshot: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
}

struct ReminderSnapshot: Sendable, Equatable {
    let title: String
    let dueDate: Date?
}

// MARK: - Dependency

struct EventKitService: Sendable {
    var fetchTodayEvents: @Sendable () async throws -> [CalendarEventSnapshot]
    var fetchDueReminders: @Sendable () async throws -> [ReminderSnapshot]
}

extension EventKitService: DependencyKey {
    static var liveValue: Self {
        let store = EKEventStore()

        return .init(
            fetchTodayEvents: {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                    return []
                }
                let startOfDay = Calendar.current.startOfDay(for: Date())
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                let pred = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
                return store.events(matching: pred)
                    .sorted { $0.startDate < $1.startDate }
                    .map {
                        CalendarEventSnapshot(
                            title: $0.title ?? "",
                            startDate: $0.startDate,
                            endDate: $0.endDate,
                            calendarTitle: $0.calendar?.title ?? ""
                        )
                    }
            },
            fetchDueReminders: {
                guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                    return []
                }
                let endOfDay = Calendar.current.date(
                    byAdding: .day, value: 1,
                    to: Calendar.current.startOfDay(for: Date())
                )!
                return try await withCheckedThrowingContinuation { continuation in
                    let pred = store.predicateForIncompleteReminders(
                        withDueDateStarting: nil,
                        ending: endOfDay,
                        calendars: nil
                    )
                    store.fetchReminders(matching: pred) { reminders in
                        let snapshots = (reminders ?? [])
                            .sorted {
                                ($0.dueDateComponents?.date ?? .distantFuture) <
                                ($1.dueDateComponents?.date ?? .distantFuture)
                            }
                            .map {
                                ReminderSnapshot(
                                    title: $0.title ?? "",
                                    dueDate: $0.dueDateComponents?.date
                                )
                            }
                        continuation.resume(returning: snapshots)
                    }
                }
            }
        )
    }

    static var testValue: Self {
        .init(
            fetchTodayEvents: {
                [
                    CalendarEventSnapshot(
                        title: "Product Review",
                        startDate: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!,
                        endDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!,
                        calendarTitle: "Work"
                    )
                ]
            },
            fetchDueReminders: {
                [ReminderSnapshot(title: "Follow up with Sarah", dueDate: Date())]
            }
        )
    }
}

extension DependencyValues {
    var eventKitService: EventKitService {
        get { self[EventKitService.self] }
        set { self[EventKitService.self] = newValue }
    }
}
