import ComposableArchitecture
import Foundation

/// Universal Dispatch — "one modal, three devices."
///
/// Replaces the previous split between `EventCreationFeature` and
/// `ReminderCreationFeature` (and the older Task Brief sheet). One modal
/// owns the entire "I extracted text from the page, where should it go?"
/// flow. Two operating modes:
///
///   - **single**: lasso / two-finger-hold → 1 captured line.
///   - **stack**: ✨ tap → OCR the whole page → N proposed lines, cycle.
///
/// Destinations (V1): Calendar, Reminders, Mail. Permission gating is
/// per-destination — we never ask up front; the first send to an
/// ungranted destination triggers the system prompt via the `Allow`
/// button in the inline permission card.
///
/// Manual `Reducer` conformance — `@Reducer` is incompatible with the
/// project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting.
struct DispatchFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        /// The line(s) being dispatched. Single mode has 1, stack mode N.
        var tasks: [DispatchTask]
        var currentIndex: Int = 0

        /// Selected integration. Drives which field pair is visible AND
        /// which permission status is consulted for the send button.
        var destination: Destination = .calendar

        // Per-destination field state. The reducer keeps all of them so
        // switching destinations doesn't lose user input. The view reads
        // only the pair relevant to `destination`.

        /// Calendar — start moment + duration. Seeded from CalendarContext
        /// on `.onAppear` (never bare `Date()`).
        var calendarStart: Date = .distantPast
        var calendarDuration: TimeInterval = 1800 // 30 min

        /// Which writable calendar the event is saved into. Nil falls
        /// through to `EKEventStore.defaultCalendarForNewEvents` on save.
        var eventCalendarID: String? = nil
        /// Available writable calendars, fetched once after event access grants.
        var eventCalendars: IdentifiedArrayOf<CalendarSnapshot> = []

        /// Reminders — list identifier + optional due moment.
        var reminderListID: String? = nil
        var reminderDue: Date? = nil
        var reminderHasTime: Bool = false

        /// Mail — recipient + subject (subject defaults to the line on save).
        var mailTo: String = ""
        var mailSubject: String = ""

        /// Optional context note for the receiver.
        var note: String = ""

        /// Per-destination permission status. Mail doesn't need
        /// permission (uses system compose); always `.fullAccess`.
        var calendarAuth: PermissionAuthStatus = .notDetermined
        var reminderAuth: PermissionAuthStatus = .notDetermined

        /// Available reminder lists, fetched once after reminder access grants.
        var reminderLists: IdentifiedArrayOf<ReminderListSnapshot> = []

        /// Line editor on/off — tap the line in read mode to enter edit mode.
        var isEditingLine: Bool = false

        /// True while upstream OCR / extraction is still in flight (set
        /// by the lasso flow when Dispatch opens before extraction
        /// completes). The view renders a "Reading…" indicator in place
        /// of the line + edit button; the reducer keeps Send disabled
        /// until the extracted text lands via `.extractionCompleted`.
        var isExtracting: Bool = false

        /// Picker presented modally on top of the Dispatch modal. Nil =
        /// no picker. The view renders an overlay with a graphical /
        /// wheel `DatePicker` or list selector when this is set.
        var openOverlay: Overlay? = nil

        enum Overlay: Equatable {
            case calendarDate
            case calendarTime
            case eventCalendar
            case reminderDue
            case reminderList
        }

        /// Resolution of each task in stack mode (drives the progress bar).
        var resolved: [UUID: Resolution] = [:]

        var saveState: SaveState = .idle
        var completion: Completion? = nil

        // MARK: - Computed

        var isStack: Bool { tasks.count > 1 }

        var currentTask: DispatchTask? {
            tasks.indices.contains(currentIndex) ? tasks[currentIndex] : nil
        }

        var currentLine: String { currentTask?.line ?? "" }

        var currentAuth: PermissionAuthStatus {
            switch destination {
            case .calendar:  return calendarAuth
            case .reminders: return reminderAuth
            case .mail:      return .fullAccess
            }
        }

        var canSend: Bool {
            currentAuth == .fullAccess
                && !isExtracting
                && !currentLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && saveState != .saving
        }

        /// Mapped to `RoutingResult.Integration` after send so the
        /// upstream history entry records the right destination.
        var currentIntegration: Integration {
            switch destination {
            case .calendar:  return .calendar
            case .reminders: return .reminders
            case .mail:      return .mail
            }
        }

        enum Destination: String, Equatable, CaseIterable, Identifiable {
            case calendar, reminders, mail
            var id: String { rawValue }
        }

        enum Resolution: Equatable {
            case sent
            case skipped
        }

        enum SaveState: Equatable {
            case idle
            case saving
            case failed(String)
        }

        enum Completion: Equatable {
            /// All tasks resolved (sent or skipped). View dismisses.
            case finished
            case cancelled
        }
    }

    @CasePathable
    enum Action: Equatable {
        // Line editor
        case lineChanged(String)
        case editingChanged(Bool)
        /// Sent by the lasso flow's OCR Task when extraction completes.
        /// Replaces the placeholder line on the current task and lifts
        /// the `isExtracting` flag.
        case extractionCompleted(String)

        // Destination + fields
        case destinationSelected(State.Destination)
        case calendarStartChanged(Date)
        /// Edits the date portion of `calendarStart`; preserves time.
        /// Used by the modal date picker so the time field doesn't get
        /// stomped when the user adjusts the calendar day.
        case calendarDateChanged(Date)
        /// Edits the time portion of `calendarStart`; preserves date.
        case calendarTimeChanged(Date)
        case calendarDurationChanged(TimeInterval)
        case eventCalendarSelected(String)
        case eventCalendarsLoaded([CalendarSnapshot])
        case reminderListSelected(String)
        case reminderDueChanged(Date?)
        case reminderHasTimeChanged(Bool)
        case mailToChanged(String)
        case mailSubjectChanged(String)
        case noteChanged(String)

        // Modal-on-modal picker presentation
        case overlayOpened(State.Overlay)
        case overlayDismissed

        // Stack navigation
        case nextTaskTapped
        case previousTaskTapped
        case taskIndexSet(Int)
        case skipTapped

        // Permissions
        case allowAccessTapped
        case permissionResolved(State.Destination, PermissionAuthStatus)
        case reminderListsLoaded([ReminderListSnapshot])

        // Commit
        case sendTapped
        case sendCompleted(EventKitIdentifier?)
        case sendFailed(String)
        case cancelTapped

        // Lifecycle
        case onAppear
        case authStatusesResolved(calendar: PermissionAuthStatus, reminder: PermissionAuthStatus)
    }

    @Dependency(\.eventKitService) var eventKit
    @Dependency(\.calendarContext) var cal

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            // MARK: - Line editor

            case .lineChanged(let new):
                guard state.tasks.indices.contains(state.currentIndex) else { return .none }
                state.tasks[state.currentIndex].line = new
                return .none

            case .editingChanged(let editing):
                state.isEditingLine = editing
                return .none

            case .extractionCompleted(let line):
                state.isExtracting = false
                if state.tasks.indices.contains(state.currentIndex) {
                    state.tasks[state.currentIndex].line = line
                }
                return .none

            // MARK: - Destination + fields

            case .destinationSelected(let dest):
                state.destination = dest
                return .none

            case .calendarStartChanged(let date):
                state.calendarStart = date
                return .none

            case .calendarDateChanged(let date):
                state.calendarStart = mergedDate(
                    datePart: date,
                    timePart: state.calendarStart,
                    cal: cal.userCalendar()
                )
                return .none

            case .calendarTimeChanged(let date):
                state.calendarStart = mergedDate(
                    datePart: state.calendarStart,
                    timePart: date,
                    cal: cal.userCalendar()
                )
                return .none

            case .calendarDurationChanged(let dur):
                state.calendarDuration = max(60, dur)
                return .none

            case .eventCalendarSelected(let id):
                state.eventCalendarID = id
                return .none

            case .eventCalendarsLoaded(let calendars):
                state.eventCalendars = IdentifiedArray(uniqueElements: calendars)
                if state.eventCalendarID == nil { state.eventCalendarID = calendars.first?.id }
                return .none

            case .reminderListSelected(let id):
                state.reminderListID = id
                return .none

            case .reminderDueChanged(let date):
                state.reminderDue = date
                if date == nil { state.reminderHasTime = false }
                return .none

            case .reminderHasTimeChanged(let hasTime):
                state.reminderHasTime = hasTime
                if hasTime && state.reminderDue == nil {
                    state.reminderDue = nextRoundHour(cal: cal)
                }
                return .none

            case .mailToChanged(let to):
                state.mailTo = to
                return .none

            case .mailSubjectChanged(let subject):
                state.mailSubject = subject
                return .none

            case .noteChanged(let note):
                state.note = note
                return .none

            // MARK: - Picker overlay presentation

            case .overlayOpened(let overlay):
                state.openOverlay = overlay
                return .none

            case .overlayDismissed:
                state.openOverlay = nil
                return .none

            // MARK: - Stack navigation

            case .nextTaskTapped:
                advanceIndex(in: &state, by: +1)
                return .none

            case .previousTaskTapped:
                advanceIndex(in: &state, by: -1)
                return .none

            case .taskIndexSet(let idx):
                if state.tasks.indices.contains(idx) {
                    state.currentIndex = idx
                    state.isEditingLine = false
                }
                return .none

            case .skipTapped:
                guard let id = state.currentTask?.id else { return .none }
                state.resolved[id] = .skipped
                // If more tasks remain, advance. Otherwise finish.
                if state.currentIndex < state.tasks.count - 1 {
                    state.currentIndex += 1
                    state.isEditingLine = false
                } else {
                    state.completion = .finished
                }
                return .none

            // MARK: - Permissions

            case .allowAccessTapped:
                let destination = state.destination
                let status = authStatus(for: destination, in: state)
                switch destination {
                case .mail:
                    return .none
                case .calendar where status == .denied || status == .restricted:
                    return .run { _ in openSystemSettings(for: .calendar) }
                case .reminders where status == .denied || status == .restricted:
                    return .run { _ in openSystemSettings(for: .reminders) }
                case .calendar:
                    return .run { send in
                        let resolved = await eventKit.requestEventAccess()
                        await send(.permissionResolved(.calendar, resolved))
                    }
                case .reminders:
                    return .run { send in
                        let resolved = await eventKit.requestReminderAccess()
                        await send(.permissionResolved(.reminders, resolved))
                    }
                }

            case .permissionResolved(let dest, let status):
                switch dest {
                case .calendar:  state.calendarAuth = status
                case .reminders: state.reminderAuth = status
                case .mail:      break
                }
                // Just-granted source unlocks its picker — pull the
                // corresponding list now so the field shows a real value
                // instead of a "—" placeholder.
                if dest == .reminders && status == .fullAccess && state.reminderLists.isEmpty {
                    return .run { send in
                        if let lists = try? await eventKit.listReminderLists() {
                            await send(.reminderListsLoaded(lists))
                        }
                    }
                    .cancellable(id: "dispatchReminderLists", cancelInFlight: true)
                }
                if dest == .calendar && status == .fullAccess && state.eventCalendars.isEmpty {
                    return .run { send in
                        if let calendars = try? await eventKit.listCalendars() {
                            await send(.eventCalendarsLoaded(calendars))
                        }
                    }
                    .cancellable(id: "dispatchEventCalendars", cancelInFlight: true)
                }
                return .none

            case .reminderListsLoaded(let lists):
                state.reminderLists = IdentifiedArray(uniqueElements: lists)
                if state.reminderListID == nil { state.reminderListID = lists.first?.id }
                return .none

            // MARK: - Send

            case .sendTapped:
                guard state.canSend, let task = state.currentTask else { return .none }
                state.saveState = .saving
                let destination = state.destination
                let line = task.line
                let note = state.note
                let calendarStart = state.calendarStart
                let calendarEnd = calendarStart.addingTimeInterval(state.calendarDuration)
                let eventCalendarID = state.eventCalendarID
                let reminderListID = state.reminderListID
                let reminderDue = state.reminderDue
                let reminderHasTime = state.reminderHasTime
                let mailTo = state.mailTo
                let mailSubject = state.mailSubject.isEmpty ? line : state.mailSubject

                return .run { send in
                    do {
                        switch destination {
                        case .calendar:
                            let draft = DraftEvent(
                                title: line,
                                notes: note,
                                startDate: calendarStart,
                                endDate: calendarEnd,
                                isAllDay: false,
                                location: "",
                                calendarID: eventCalendarID,
                                alarmsMinutesBefore: []
                            )
                            let id = try await eventKit.createEvent(draft)
                            await send(.sendCompleted(id))
                        case .reminders:
                            let draft = DraftReminder(
                                title: line,
                                notes: note,
                                dueDate: reminderDue,
                                hasTime: reminderHasTime,
                                priority: 0,
                                listID: reminderListID
                            )
                            let id = try await eventKit.createReminder(draft)
                            await send(.sendCompleted(id))
                        case .mail:
                            try openMailto(to: mailTo, subject: mailSubject, body: note)
                            await send(.sendCompleted(nil))
                        }
                    } catch {
                        await send(.sendFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: "dispatchSend", cancelInFlight: true)

            case .sendCompleted:
                state.saveState = .idle
                if let id = state.currentTask?.id {
                    state.resolved[id] = .sent
                }
                // Stack mode: advance to the next unresolved task. Single
                // mode (or last task in stack): finish.
                if state.isStack,
                   let nextIdx = nextUnresolvedIndex(in: state) {
                    state.currentIndex = nextIdx
                    state.isEditingLine = false
                } else {
                    state.completion = .finished
                }
                return .none

            case .sendFailed(let message):
                state.saveState = .failed(message)
                return .none

            case .cancelTapped:
                state.completion = .cancelled
                return .none

            // MARK: - Lifecycle

            case .onAppear:
                // Seed calendarStart if still at the placeholder. Default
                // is `now` — today, current moment. The user picks a
                // specific time via the Time field if they want; we
                // don't pre-anchor to tomorrow or to a rounded hour.
                if state.calendarStart == .distantPast {
                    state.calendarStart = cal.now()
                }
                return .run { send in
                    // Snapshot current statuses without prompting; the
                    // permission card and Allow button handle prompting
                    // explicitly per the design ("ask once, on the action").
                    let calStatus = eventKit.eventAuthStatus()
                    let remStatus = eventKit.reminderAuthStatus()
                    await send(.authStatusesResolved(calendar: calStatus, reminder: remStatus))
                }
                .cancellable(id: "dispatchOnAppear", cancelInFlight: true)

            case .authStatusesResolved(let calStatus, let remStatus):
                state.calendarAuth = calStatus
                state.reminderAuth = remStatus
                // Concurrently fetch lists for any source that's already
                // granted — these power the calendar/list pickers.
                var effects: [Effect<Action>] = []
                if remStatus == .fullAccess && state.reminderLists.isEmpty {
                    effects.append(.run { send in
                        if let lists = try? await eventKit.listReminderLists() {
                            await send(.reminderListsLoaded(lists))
                        }
                    }.cancellable(id: "dispatchReminderLists", cancelInFlight: true))
                }
                if calStatus == .fullAccess && state.eventCalendars.isEmpty {
                    effects.append(.run { send in
                        if let calendars = try? await eventKit.listCalendars() {
                            await send(.eventCalendarsLoaded(calendars))
                        }
                    }.cancellable(id: "dispatchEventCalendars", cancelInFlight: true))
                }
                return effects.isEmpty ? .none : .merge(effects)
            }
        }
    }
}

// MARK: - Helpers

private func advanceIndex(in state: inout DispatchFeature.State, by delta: Int) {
    let target = state.currentIndex + delta
    if state.tasks.indices.contains(target) {
        state.currentIndex = target
        state.isEditingLine = false
    }
}

private func authStatus(
    for destination: DispatchFeature.State.Destination,
    in state: DispatchFeature.State
) -> PermissionAuthStatus {
    switch destination {
    case .calendar:  return state.calendarAuth
    case .reminders: return state.reminderAuth
    case .mail:      return .fullAccess
    }
}

private func nextUnresolvedIndex(in state: DispatchFeature.State) -> Int? {
    let indices = state.tasks.indices
    for i in indices where i != state.currentIndex {
        let id = state.tasks[i].id
        if state.resolved[id] == nil { return i }
    }
    return nil
}

/// Combine the y/m/d of one Date with the hour/minute of another.
/// Used to keep Date and Time as independently editable fields even
/// though they share a single `calendarStart` storage on State.
private func mergedDate(datePart: Date, timePart: Date, cal: Calendar) -> Date {
    let dateComponents = cal.dateComponents([.year, .month, .day], from: datePart)
    let timeComponents = cal.dateComponents([.hour, .minute], from: timePart)
    var merged = DateComponents()
    merged.year = dateComponents.year
    merged.month = dateComponents.month
    merged.day = dateComponents.day
    merged.hour = timeComponents.hour
    merged.minute = timeComponents.minute
    return cal.date(from: merged) ?? datePart
}

private func nextRoundHour(cal: CalendarContext) -> Date {
    let now = cal.now()
    let userCal = cal.userCalendar()
    let inOneHour = userCal.date(byAdding: .hour, value: 1, to: now) ?? now
    let hour = userCal.component(.hour, from: inOneHour)
    let dayAnchor = userCal.startOfDay(for: inOneHour)
    return userCal.date(bySettingHour: hour, minute: 0, second: 0, of: dayAnchor) ?? inOneHour
}

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private func openSystemSettings(for dest: DispatchFeature.State.Destination) {
    #if canImport(UIKit)
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
    #elseif canImport(AppKit)
    let path: String
    switch dest {
    case .calendar:  path = "Privacy_Calendars"
    case .reminders: path = "Privacy_Reminders"
    case .mail:      path = ""
    }
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") {
        NSWorkspace.shared.open(url)
    }
    #endif
}

/// Cross-platform "open Mail compose" via mailto: URL. V1 stub —
/// MFMailComposeViewController on iOS could replace this for a
/// branded experience without leaving the app.
private func openMailto(to: String, subject: String, body: String) throws {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = to
    components.queryItems = [
        URLQueryItem(name: "subject", value: subject),
        URLQueryItem(name: "body", value: body),
    ].filter { ($0.value ?? "").isEmpty == false }
    guard let url = components.url else {
        throw NSError(domain: "DispatchFeature", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Could not build a Mail URL."
        ])
    }
    #if canImport(UIKit)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}

// MARK: - Task value type

/// One captured line ready for dispatch. Carries the originating
/// `InkTask` so the routing pipeline can record a `NoteHistoryDraft`
/// entry after a successful send.
struct DispatchTask: Equatable, Identifiable {
    let id: UUID
    var line: String
    var originatingTask: InkTask?

    init(id: UUID = UUID(), line: String, originatingTask: InkTask? = nil) {
        self.id = id
        self.line = line
        self.originatingTask = originatingTask
    }

    /// Construct a single-task state seeded from an `InkTask` (the
    /// classic lasso / hold flow). Calendar is the default destination
    /// when the task arrived through the calendar route.
    static func single(from task: InkTask) -> DispatchTask {
        DispatchTask(line: task.title, originatingTask: task)
    }
}
