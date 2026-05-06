import Foundation
import EventKit

actor RoutingService {
    static let shared = RoutingService()

    private let store = EKEventStore()

    // MARK: - Reminders

    func routeToReminders(_ task: InkTask) async throws -> RoutingResult {
        try await requestAccess(for: .reminder)

        let reminder = EKReminder(eventStore: store)
        reminder.title = task.title
        if !task.body.isEmpty { reminder.notes = task.body }
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = task.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw RoutingError.saveFailed(error.localizedDescription)
        }

        let identifier = reminder.calendarItemIdentifier
        return RoutingResult(
            integration: .reminders,
            destinationURL: "x-apple-reminderkit://\(identifier)",
            eventKitIdentifier: identifier
        )
    }

    // MARK: - Calendar

    /// Returns `.needsCalendarUI` when `task.dueDate` is nil — caller should present
    /// `EventEditView` so the user can supply the time themselves.
    /// Permission is always requested first so `EKEventEditViewController` has access when presented.
    func routeToCalendar(_ task: InkTask) async throws -> RoutingOutcome {
        try await requestAccess(for: .event)

        guard let startDate = task.dueDate else {
            return .needsCalendarUI
        }

        let event = EKEvent(eventStore: store)
        event.title = task.title
        if !task.body.isEmpty { event.notes = task.body }
        event.startDate = startDate
        event.endDate = task.context.calendarEndDate ?? startDate.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw RoutingError.saveFailed(error.localizedDescription)
        }

        return .success(RoutingResult(
            integration: .calendar,
            destinationURL: "calshow://\(event.startDate.timeIntervalSince1970)",
            eventKitIdentifier: event.eventIdentifier
        ))
    }

    // MARK: - History

    /// Fetch a live calendar event by EventKit identifier for history re-open.
    func calendarEvent(withIdentifier identifier: String) -> EKEvent? {
        store.event(withIdentifier: identifier)
    }

    // MARK: - Permission

    private func requestAccess(for entityType: EKEntityType) async throws {
        let status = EKEventStore.authorizationStatus(for: entityType)
        guard status != .fullAccess else { return }
        guard status == .notDetermined else {
            throw RoutingError.permissionDenied(entityType == .reminder ? .reminders : .calendar)
        }
        let granted: Bool
        do {
            granted = entityType == .reminder
                ? try await store.requestFullAccessToReminders()
                : try await store.requestFullAccessToEvents()
        } catch {
            throw RoutingError.permissionDenied(entityType == .reminder ? .reminders : .calendar)
        }
        guard granted else {
            throw RoutingError.permissionDenied(entityType == .reminder ? .reminders : .calendar)
        }
    }
}
