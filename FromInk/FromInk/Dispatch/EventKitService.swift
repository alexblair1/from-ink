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
    /// `EKEvent.eventIdentifier`. Shared across all occurrences of a
    /// recurring series, so a single `CalendarItemLink` covers the
    /// whole series. May change if the event is moved between calendars
    /// — `externalIdentifier` is the durable fallback.
    let localIdentifier: String
    /// `EKCalendarItem.calendarItemExternalIdentifier`. Stable across
    /// devices via iCloud / CalDAV. Nil for purely-local calendars.
    let externalIdentifier: String?
    /// True when the underlying EKEvent has at least one recurrence
    /// rule. Drives the "this notebook will cover all instances of this
    /// meeting" copy on the Create / Link confirmation.
    let hasRecurrenceRules: Bool
}

struct ReminderSnapshot: Sendable, Equatable {
    let title: String
    let dueDate: Date?
    /// True if the reminder has no specific time of day — either no due
    /// date at all (`dueDateComponents == nil`) or a due date with no
    /// `hour` component. Matches Apple's "Today, anytime" semantics.
    let isAllDay: Bool
    /// `EKCalendarItem.calendarItemIdentifier`. EKReminder uses the
    /// shared calendar-item identifier rather than a reminder-specific
    /// one. Same staleness rules as event `localIdentifier`.
    let localIdentifier: String
    /// `EKCalendarItem.calendarItemExternalIdentifier`. Same semantics
    /// as on `CalendarEventSnapshot`.
    let externalIdentifier: String?
}

/// Sendable view of an EKCalendar. `id` is `calendarIdentifier`,
/// stable across launches.
struct CalendarSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    /// CGColor packed to a hex string ("#RRGGBBAA"). Lets the UI render
    /// the calendar accent without importing AppKit/UIKit colors at the
    /// snapshot boundary.
    let colorHex: String
    let isWritable: Bool
    let sourceTitle: String
}

struct ReminderListSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let colorHex: String
    let isWritable: Bool
}

/// Editable draft of an event. Crosses the dependency boundary so the
/// creation feature never touches `EKEvent` directly. New optional
/// fields default-initialize so existing callers (the Dispatch send
/// path) compile without touching them; the UI rolls in incrementally.
struct DraftEvent: Sendable, Equatable {
    var title: String
    var notes: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String
    /// Optional geo-coordinate paired with `location`. When set, the
    /// saved event carries an `EKStructuredLocation`, which Calendar.app
    /// uses to render the inline map preview. Lat/lon stored as plain
    /// `Double`s so the type stays `Sendable`/`Equatable` without
    /// importing `CoreLocation` at the snapshot boundary.
    var locationCoordinate: LocationCoordinate? = nil
    var url: URL? = nil
    /// `calendarIdentifier` of the target calendar. Nil = use the default
    /// calendar for events.
    var calendarID: String?
    /// Minutes-before-event alarm offsets. `[15]` = one alarm 15 min
    /// before; empty = no alarms.
    var alarmsMinutesBefore: [Int]
    /// Optional simple recurrence. Maps to a single `EKRecurrenceRule`
    /// on save. `.never` = no rule attached.
    var recurrence: EventRecurrence = .never
    /// True when the source event had a recurrence rule that doesn't
    /// fit our six quick-pick patterns (custom `byDay`, COUNT/UNTIL,
    /// non-standard intervals, etc.). Set by `init(event:)`.
    ///
    /// `apply(_:to:store:)` honors this flag and *skips* the
    /// recurrence rewrite — i.e., editing other fields on a complex
    /// recurring event preserves the original rule. The UI is
    /// expected to clear this flag explicitly when the user picks a
    /// new recurrence (deliberately committing to one of our
    /// quick-picks), at which point apply does rewrite the rules.
    var hasUnsupportedRecurrence: Bool = false
}

struct LocationCoordinate: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}

/// Simple recurrence options for the Dispatch Calendar destination.
/// Mirrors Apple Calendar's quick-pick rotation; the EKRecurrenceRule
/// it maps to is constructed on save.
enum EventRecurrence: String, Sendable, Equatable, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly

    var id: String { rawValue }
}

struct DraftReminder: Sendable, Equatable {
    var title: String
    var notes: String
    /// Nil means "no due date" — Reminders accepts undated reminders.
    var dueDate: Date?
    /// True if the due date includes a specific time (`hour` component).
    /// False = "anytime that day."
    var hasTime: Bool
    /// 0 = none, 1 = high, 5 = medium, 9 = low. Matches `EKReminder.priority`.
    var priority: Int
    /// `calendarIdentifier` of the target list. Nil = default list.
    var listID: String?
}

/// Opaque stable identifier returned by EventKit on save. Stored in
/// `NoteHistoryEntry.taskEventKitIdentifier` to re-open the original
/// EK record later.
typealias EventKitIdentifier = String

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

    // MARK: - Writes (replace EventKitUI on macOS, supplement on iOS)

    /// All writable calendars the user has connected. The creation UI
    /// uses this to populate the calendar picker; the default selection
    /// matches `EKEventStore.defaultCalendarForNewEvents` when present.
    var listCalendars: @Sendable () async throws -> [CalendarSnapshot]
    var listReminderLists: @Sendable () async throws -> [ReminderListSnapshot]

    /// Persist a draft as a new EKEvent. Returns the calendar
    /// identifier so the dispatch history entry can re-open the record.
    var createEvent: @Sendable (DraftEvent) async throws -> EventKitIdentifier
    /// Update an existing event by identifier with the draft's fields.
    var updateEvent: @Sendable (EventKitIdentifier, DraftEvent) async throws -> Void
    var createReminder: @Sendable (DraftReminder) async throws -> EventKitIdentifier
    var updateReminder: @Sendable (EventKitIdentifier, DraftReminder) async throws -> Void

    /// Fetch the current state of a saved event/reminder so the editor
    /// can pre-populate when re-opening from dispatch history. Returns
    /// nil if the record was deleted from EventKit.
    var fetchEventDraft: @Sendable (EventKitIdentifier) async throws -> DraftEvent?
    var fetchReminderDraft: @Sendable (EventKitIdentifier) async throws -> DraftReminder?

    var deleteEvent: @Sendable (EventKitIdentifier) async throws -> Void
    var deleteReminder: @Sendable (EventKitIdentifier) async throws -> Void

    /// Resolve a calendar item by its identifier with external-ID
    /// fallback. Used by `CalendarItemLinkValidator` to detect orphan
    /// links + auto-heal stale `localIdentifier`s (e.g., when the user
    /// moves an event to a different calendar — EventKit issues a new
    /// local ID, but `calendarItemExternalIdentifier` carries over).
    ///
    /// Returns `nil` when neither the local ID nor the external ID
    /// resolves to a live EK record — at which point the link is
    /// genuinely orphaned and should be deleted.
    ///
    /// Resolution semantics:
    /// 1. Try `event(withIdentifier:)` / `calendarItem(withIdentifier:)`
    ///    on `localID`. If found → return its current `localIdentifier`
    ///    and `externalIdentifier`.
    /// 2. Else if `externalID` is non-nil, try
    ///    `calendarItems(withExternalIdentifier:)`. If exactly one
    ///    survivor → return its current identifiers (caller can rewrite
    ///    the stored `localIdentifier` if it changed).
    /// 3. Else → return `nil`.
    var resolveCalendarItem: @Sendable (
        _ localID: String,
        _ externalID: String?,
        _ kind: CalendarItemKind
    ) async -> CalendarItemResolution?
}

/// Result of a successful EK lookup — the identifiers as they currently
/// exist on the record. Callers compare with the stored values to detect
/// whether `localIdentifier` needs to be rewritten on the link.
struct CalendarItemResolution: Sendable, Equatable {
    let localIdentifier: String
    let externalIdentifier: String?
}

// MARK: - Errors

enum EventKitWriteError: Error, LocalizedError, Equatable {
    case notAuthorized
    case calendarUnavailable
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar or Reminders access is required."
        case .calendarUnavailable: return "No writable calendar is available."
        case .recordNotFound: return "This item is no longer in your calendar."
        }
    }
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
                        isAllDay: $0.isAllDay,
                        localIdentifier: $0.eventIdentifier ?? "",
                        externalIdentifier: $0.calendarItemExternalIdentifier,
                        hasRecurrenceRules: !($0.recurrenceRules ?? []).isEmpty
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
                                isAllDay: isAllDay,
                                localIdentifier: reminder.calendarItemIdentifier,
                                externalIdentifier: reminder.calendarItemExternalIdentifier
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
            },
            listCalendars: {
                guard eventStatus() == .fullAccess else { throw EventKitWriteError.notAuthorized }
                store.reset()
                return store.calendars(for: .event)
                    .filter { $0.allowsContentModifications }
                    .map(CalendarSnapshot.init(calendar:))
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            },
            listReminderLists: {
                guard reminderStatus() == .fullAccess else { throw EventKitWriteError.notAuthorized }
                store.reset()
                return store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
                    .map(ReminderListSnapshot.init(calendar:))
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            },
            createEvent: { draft in
                guard eventStatus() == .fullAccess else { throw EventKitWriteError.notAuthorized }
                let event = EKEvent(eventStore: store)
                try apply(draft, to: event, store: store)
                try store.save(event, span: .thisEvent, commit: true)
                return event.eventIdentifier
            },
            updateEvent: { id, draft in
                guard eventStatus() == .fullAccess else { throw EventKitWriteError.notAuthorized }
                store.reset()
                guard let event = store.event(withIdentifier: id) else {
                    throw EventKitWriteError.recordNotFound
                }
                try apply(draft, to: event, store: store)
                try store.save(event, span: .thisEvent, commit: true)
            },
            createReminder: { draft in
                guard reminderStatus() == .fullAccess else { throw EventKitWriteError.notAuthorized }
                let reminder = EKReminder(eventStore: store)
                try apply(draft, to: reminder, store: store)
                try store.save(reminder, commit: true)
                return reminder.calendarItemIdentifier
            },
            updateReminder: { id, draft in
                guard reminderStatus() == .fullAccess else { throw EventKitWriteError.notAuthorized }
                store.reset()
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                    throw EventKitWriteError.recordNotFound
                }
                try apply(draft, to: reminder, store: store)
                try store.save(reminder, commit: true)
            },
            fetchEventDraft: { id in
                store.reset()
                guard let event = store.event(withIdentifier: id) else { return nil }
                return DraftEvent(event: event)
            },
            fetchReminderDraft: { id in
                store.reset()
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                    return nil
                }
                return DraftReminder(reminder: reminder)
            },
            deleteEvent: { id in
                store.reset()
                guard let event = store.event(withIdentifier: id) else {
                    throw EventKitWriteError.recordNotFound
                }
                try store.remove(event, span: .thisEvent, commit: true)
            },
            deleteReminder: { id in
                store.reset()
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                    throw EventKitWriteError.recordNotFound
                }
                try store.remove(reminder, commit: true)
            },
            resolveCalendarItem: { localID, externalID, kind in
                // Drop EK's in-memory cache before every resolution.
                // The validator is invoked on `EKEventStoreChanged`, so
                // by definition something has changed — we want the
                // post-change state, not a cached pre-change snapshot.
                store.reset()

                // 1. Direct local lookup. For events the dedicated API
                //    is `event(withIdentifier:)`; for reminders we use
                //    the generic `calendarItem(withIdentifier:)`.
                switch kind {
                case .event:
                    if let event = store.event(withIdentifier: localID) {
                        return CalendarItemResolution(
                            localIdentifier: event.eventIdentifier ?? localID,
                            externalIdentifier: event.calendarItemExternalIdentifier
                        )
                    }
                case .reminder:
                    if let item = store.calendarItem(withIdentifier: localID) {
                        return CalendarItemResolution(
                            localIdentifier: item.calendarItemIdentifier,
                            externalIdentifier: item.calendarItemExternalIdentifier
                        )
                    }
                }

                // 2. External-ID fallback. Returns 0..N items; we treat
                //    1 as a successful resolution. 0 = orphan, >1 = the
                //    external ID matches multiple records (rare, happens
                //    with detached recurring instances) and we abstain
                //    rather than guess which one the user meant.
                guard let externalID, !externalID.isEmpty else { return nil }
                let matches = store.calendarItems(withExternalIdentifier: externalID)
                    .filter { item in
                        switch kind {
                        case .event:    return item is EKEvent
                        case .reminder: return item is EKReminder
                        }
                    }
                guard matches.count == 1, let item = matches.first else { return nil }
                let resolvedLocalID: String = {
                    if let event = item as? EKEvent { return event.eventIdentifier ?? "" }
                    return item.calendarItemIdentifier
                }()
                return CalendarItemResolution(
                    localIdentifier: resolvedLocalID,
                    externalIdentifier: item.calendarItemExternalIdentifier
                )
            }
        )
    }

    static var testValue: Self {
        let canned = CalendarEventSnapshot(
            title: "Product Review",
            startDate: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!,
            endDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!,
            calendarTitle: "Work",
            isAllDay: false,
            localIdentifier: "test-event-id",
            externalIdentifier: "test-event-external-id",
            hasRecurrenceRules: false
        )
        let cannedReminder = ReminderSnapshot(
            title: "Follow up with Sarah",
            dueDate: Date(),
            isAllDay: false,
            localIdentifier: "test-reminder-id",
            externalIdentifier: "test-reminder-external-id"
        )

        let cannedCalendar = CalendarSnapshot(
            id: "test-cal-1",
            title: "Work",
            colorHex: "#3478F6FF",
            isWritable: true,
            sourceTitle: "iCloud"
        )
        let cannedList = ReminderListSnapshot(
            id: "test-list-1",
            title: "Reminders",
            colorHex: "#FF3B30FF",
            isWritable: true
        )

        return .init(
            fetchTodayEvents: { [canned] },
            fetchDueReminders: { [cannedReminder] },
            fetchEvents: { _ in [canned] },
            fetchReminders: { _ in [cannedReminder] },
            eventAuthStatus: { .fullAccess },
            reminderAuthStatus: { .fullAccess },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .fullAccess },
            listCalendars: { [cannedCalendar] },
            listReminderLists: { [cannedList] },
            createEvent: { _ in "test-event-id" },
            updateEvent: { _, _ in },
            createReminder: { _ in "test-reminder-id" },
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in },
            // Default `testValue` posture: every link is alive. Tests
            // that need orphan behavior replace this with the dependency
            // override pattern (`withDependencies { $0.eventKitService = ... }`).
            resolveCalendarItem: { localID, externalID, _ in
                CalendarItemResolution(
                    localIdentifier: localID,
                    externalIdentifier: externalID
                )
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

// MARK: - EK ⇄ Snapshot bridges

private func apply(_ draft: DraftEvent, to event: EKEvent, store: EKEventStore) throws {
    event.title = draft.title
    event.notes = draft.notes.isEmpty ? nil : draft.notes
    event.startDate = draft.startDate
    event.endDate = draft.endDate
    event.isAllDay = draft.isAllDay

    // Location text + optional structured location for the map preview.
    // A structured location requires a title — refusing to fabricate
    // one means the (coordinate-without-text) case skips structured
    // entirely. The user's text becomes the structured title verbatim
    // when both are present.
    let trimmedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
    event.location = trimmedLocation.isEmpty ? nil : trimmedLocation
    if let coord = draft.locationCoordinate, !trimmedLocation.isEmpty {
        let structured = EKStructuredLocation(title: trimmedLocation)
        structured.geoLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        structured.radius = 0
        event.structuredLocation = structured
    } else {
        event.structuredLocation = nil
    }

    event.url = draft.url

    let targetCalendar = draft.calendarID.flatMap(store.calendar(withIdentifier:))
        ?? store.defaultCalendarForNewEvents
    guard let calendar = targetCalendar else { throw EventKitWriteError.calendarUnavailable }
    event.calendar = calendar

    // Reset alarms before applying — EventKit appends otherwise.
    if let existing = event.alarms { existing.forEach(event.removeAlarm(_:)) }
    for minutes in draft.alarmsMinutesBefore {
        event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
    }

    // Recurrence — skip the rewrite when the source event carried a
    // pattern outside our quick-picks AND the user hasn't deliberately
    // changed it (the UI is expected to clear `hasUnsupportedRecurrence`
    // on explicit selection). Otherwise reset any existing rules and
    // add the chosen one. `.never` means no recurrence; one-shot event.
    if !draft.hasUnsupportedRecurrence {
        if let existing = event.recurrenceRules { existing.forEach(event.removeRecurrenceRule(_:)) }
        if let rule = ekRecurrenceRule(for: draft.recurrence) {
            event.addRecurrenceRule(rule)
        }
    }
}

private func ekRecurrenceRule(for recurrence: EventRecurrence) -> EKRecurrenceRule? {
    switch recurrence {
    case .never:    return nil
    case .daily:    return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
    case .weekly:   return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
    case .biweekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
    case .monthly:  return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
    case .yearly:   return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
    }
}

private func apply(_ draft: DraftReminder, to reminder: EKReminder, store: EKEventStore) throws {
    reminder.title = draft.title
    reminder.notes = draft.notes.isEmpty ? nil : draft.notes
    reminder.priority = draft.priority

    if let due = draft.dueDate {
        let units: Set<Calendar.Component> = draft.hasTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        reminder.dueDateComponents = Calendar.autoupdatingCurrent.dateComponents(units, from: due)
    } else {
        reminder.dueDateComponents = nil
    }

    let targetList = draft.listID.flatMap(store.calendar(withIdentifier:))
        ?? store.defaultCalendarForNewReminders()
    guard let list = targetList else { throw EventKitWriteError.calendarUnavailable }
    reminder.calendar = list
}

private extension CalendarSnapshot {
    init(calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: cgColorHex(calendar.cgColor),
            isWritable: calendar.allowsContentModifications,
            sourceTitle: calendar.source?.title ?? ""
        )
    }
}

private extension ReminderListSnapshot {
    init(calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: cgColorHex(calendar.cgColor),
            isWritable: calendar.allowsContentModifications
        )
    }
}

extension DraftEvent {
    init(event: EKEvent) {
        // Round-trip location: prefer the structured form (carries the
        // coordinate Calendar.app uses for the map preview), fall back
        // to plain text when no structured location is attached.
        let locationText: String
        let locationCoord: LocationCoordinate?
        if let structured = event.structuredLocation {
            locationText = structured.title ?? event.location ?? ""
            if let geo = structured.geoLocation {
                locationCoord = LocationCoordinate(
                    latitude: geo.coordinate.latitude,
                    longitude: geo.coordinate.longitude
                )
            } else {
                locationCoord = nil
            }
        } else {
            locationText = event.location ?? ""
            locationCoord = nil
        }

        // Recurrence: read the first rule and decide whether it fits
        // one of our quick-picks. Anything else is preserved as
        // "unsupported" so `apply(_:to:store:)` can skip the rewrite
        // and leave the original rule intact.
        let firstRule = event.recurrenceRules?.first
        let recognized = EventRecurrence(rule: firstRule)
        let unsupported = firstRule != nil && recognized == .never

        self.init(
            title: event.title ?? "",
            notes: event.notes ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: locationText,
            locationCoordinate: locationCoord,
            url: event.url,
            calendarID: event.calendar?.calendarIdentifier,
            alarmsMinutesBefore: (event.alarms ?? []).compactMap { alarm in
                let offset = alarm.relativeOffset
                guard offset < 0 else { return nil }
                return Int((-offset / 60).rounded())
            },
            recurrence: recognized,
            hasUnsupportedRecurrence: unsupported
        )
    }
}

extension EventRecurrence {
    /// Maps an `EKRecurrenceRule` back to our simplified enum. Anything
    /// outside the six quick-pick patterns returns `.never` —
    /// `DraftEvent.init(event:)` pairs this with `hasUnsupportedRecurrence`
    /// so apply can decide whether to preserve the original rule or
    /// rewrite it to the user's selection.
    init(rule: EKRecurrenceRule?) {
        guard let rule else { self = .never; return }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1):    self = .daily
        case (.weekly, 1):   self = .weekly
        case (.weekly, 2):   self = .biweekly
        case (.monthly, 1):  self = .monthly
        case (.yearly, 1):   self = .yearly
        default:             self = .never
        }
    }
}

extension DraftReminder {
    init(reminder: EKReminder) {
        let components = reminder.dueDateComponents
        let date = components?.date
        let hasTime = components?.hour != nil
        self.init(
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            dueDate: date,
            hasTime: hasTime,
            priority: reminder.priority,
            listID: reminder.calendar?.calendarIdentifier
        )
    }

}

/// Pack a CGColor's RGBA into a stable "#RRGGBBAA" string so snapshot
/// types don't need to import AppKit/UIKit. Falls back to opaque black.
private func cgColorHex(_ color: CGColor?) -> String {
    guard let color, let comps = color.components, comps.count >= 3 else {
        return "#000000FF"
    }
    let r = UInt8(max(0, min(1, comps[0])) * 255)
    let g = UInt8(max(0, min(1, comps[1])) * 255)
    let b = UInt8(max(0, min(1, comps[2])) * 255)
    let a = UInt8(max(0, min(1, comps.count >= 4 ? comps[3] : 1)) * 255)
    return String(format: "#%02X%02X%02X%02X", r, g, b, a)
}
