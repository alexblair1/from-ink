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
        /// New-event duration when the user hasn't edited the End fields.
        /// Tests assert preservation of the *current* duration across
        /// start edits — not literal equality with this constant — so
        /// changing the default here won't ripple through assertions.
        static let defaultEventDuration: TimeInterval = 1800
        /// Floor between start and end. EKEvent rejects `end <= start`;
        /// the reducer clamps direct end edits and shielding logic floors
        /// preserved-duration math here to keep state valid.
        static let minEventDuration: TimeInterval = 60

        /// The line(s) being dispatched. Single mode has 1, stack mode N.
        var tasks: [DispatchTask]
        var currentIndex: Int = 0

        /// Selected integration. Drives which field pair is visible AND
        /// which permission status is consulted for the send button.
        var destination: Destination = .calendar

        // Per-destination field state. The reducer keeps all of them so
        // switching destinations doesn't lose user input. The view reads
        // only the pair relevant to `destination`.

        /// Calendar — start + end moments. Nil until `.onAppear` seeds
        /// from CalendarContext (no `.distantPast` sentinels — the CLAUDE.md
        /// "no fake placeholders" rule). End defaults to start + the
        /// `defaultEventDuration` constant; subsequent edits to start
        /// preserve the (end − start) duration by sliding end along.
        var calendarStart: Date? = nil
        var calendarEnd: Date? = nil

        /// Which writable calendar the event is saved into. Nil falls
        /// through to `EKEventStore.defaultCalendarForNewEvents` on save.
        var eventCalendarID: String? = nil
        /// Available writable calendars, fetched once after event access grants.
        var eventCalendars: IdentifiedArrayOf<CalendarSnapshot> = []

        /// Optional URL attached to the event (zoom link, doc link, etc.).
        /// Stored as `String` because the user types free text — whatever
        /// they type stays in the form. On send we trim whitespace, run
        /// `URL(string:)`, AND require a scheme — `URL(string:)` is
        /// surprisingly permissive and accepts schemeless input like
        /// `"example.com"` as a relative URL, which Calendar.app can't
        /// render as a tappable link. Requiring a scheme matches what
        /// users actually want when they paste a URL field.
        var eventURL: String = ""

        /// Event location — free text (e.g. "Conference Room A") OR a
        /// MapKit autocomplete pick. When the user taps a suggestion we
        /// also store the resolved coordinate so the saved event carries
        /// an `EKStructuredLocation`, which Calendar.app uses to render
        /// the inline map preview. Hand-typed locations have no
        /// coordinate and save as a plain string — same as typing in
        /// Apple Calendar without picking a suggestion.
        var eventLocation: String = ""
        var eventLocationCoordinate: LocationCoordinate? = nil

        /// Live MapKit autocomplete results for the current location
        /// query. Empty when the user hasn't typed yet, when their
        /// query is empty, or when they just picked a suggestion (we
        /// clear on tap so the list collapses without an extra round
        /// trip through the completer).
        var locationSuggestions: IdentifiedArrayOf<LocationSuggestion> = []

        /// Recurrence preset. `.never` (default) maps to a single-shot
        /// event with no `EKRecurrenceRule`. Picking any other value
        /// adds the corresponding rule on save via `DraftEvent.apply`.
        /// We don't expose custom (byDay / interval / endCount) rules
        /// — the six presets match Apple Calendar's quick-pick rotation.
        var eventRecurrence: EventRecurrence = .never

        /// Single-alarm offset, in minutes before event start. `nil`
        /// (default) means no alarm. v1 exposes exactly one preset
        /// alarm at a time; the send path wraps the Int into the
        /// `[Int]` shape `DraftEvent.alarmsMinutesBefore` expects. The
        /// preset list lives in the wiring layer — only the picker
        /// cares about which Int values are "presets" vs arbitrary.
        var eventAlarmMinutesBefore: Int? = nil

        /// Whether the modal is creating a new event or editing an
        /// existing one. `.edit(id)` is set by `openForEditingEvent`,
        /// which also triggers `fetchEventDraft` to populate state
        /// fields from the loaded event via `editingEventLoaded`. The
        /// send path branches on this: `.edit` → `updateEvent` (in
        /// place), `.create` → `createEvent` (returns a new id).
        var mode: Mode = .create

        enum Mode: Equatable {
            case create
            case edit(EventKitIdentifier)

            /// Convenience for the wiring — true iff editing an existing event.
            var isEditing: Bool {
                if case .edit = self { return true }
                return false
            }
        }

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
            case calendarEndDate
            case calendarEndTime
            case eventCalendar
            case eventRecurrence
            case eventAlarm
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

        /// Mail subject as used by both the view (placeholder/display)
        /// and the send path (mailto URL). Falls back to the current
        /// line when the user hasn't typed an explicit subject — single
        /// rule, single site, no chance of the view and the reducer
        /// drifting from each other on what "empty subject" means.
        var effectiveMailSubject: String {
            mailSubject.isEmpty ? currentLine : mailSubject
        }

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
        /// Edits the date portion of `calendarStart`; preserves time.
        /// Used by the modal date picker so the time field doesn't get
        /// stomped when the user adjusts the calendar day.
        case calendarDateChanged(Date)
        /// Edits the time portion of `calendarStart`; preserves date.
        case calendarTimeChanged(Date)
        /// Edits the date portion of `calendarEnd`; preserves time.
        case calendarEndDateChanged(Date)
        /// Edits the time portion of `calendarEnd`; preserves date.
        case calendarEndTimeChanged(Date)
        case eventCalendarSelected(String)
        case eventCalendarsLoaded([CalendarSnapshot])
        case eventURLChanged(String)
        case eventRecurrenceSelected(EventRecurrence)
        case eventAlarmSelected(Int?)
        case openForEditingEvent(EventKitIdentifier)
        case editingEventLoaded(DraftEvent)
        case editingEventLoadFailed(String)
        case eventLocationChanged(String)
        case locationSuggestionsUpdated([LocationSuggestion])
        case locationSuggestionTapped(LocationSuggestion)
        case locationResolved(ResolvedLocation)
        case locationResolveFailed
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
    @Dependency(\.locationSearchService) var locationSearch

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

            case .calendarDateChanged(let date):
                let timePart = state.calendarStart ?? cal.now()
                let merged = mergedDate(datePart: date, timePart: timePart, cal: cal)
                shiftCalendarStart(in: &state, to: merged)
                return .none

            case .calendarTimeChanged(let date):
                let datePart = state.calendarStart ?? cal.now()
                let merged = mergedDate(datePart: datePart, timePart: date, cal: cal)
                shiftCalendarStart(in: &state, to: merged)
                return .none

            case .calendarEndDateChanged(let date):
                let timePart = state.calendarEnd ?? cal.now()
                let merged = mergedDate(datePart: date, timePart: timePart, cal: cal)
                state.calendarEnd = clampEndAfterStart(end: merged, start: state.calendarStart)
                return .none

            case .calendarEndTimeChanged(let date):
                let datePart = state.calendarEnd ?? cal.now()
                let merged = mergedDate(datePart: datePart, timePart: date, cal: cal)
                state.calendarEnd = clampEndAfterStart(end: merged, start: state.calendarStart)
                return .none

            case .eventCalendarSelected(let id):
                state.eventCalendarID = id
                return .none

            case .eventCalendarsLoaded(let calendars):
                state.eventCalendars = IdentifiedArray(uniqueElements: calendars)
                if state.eventCalendarID == nil { state.eventCalendarID = calendars.first?.id }
                return .none

            case .eventURLChanged(let url):
                state.eventURL = url
                return .none

            case .eventRecurrenceSelected(let recurrence):
                state.eventRecurrence = recurrence
                return .none

            case .eventAlarmSelected(let minutes):
                state.eventAlarmMinutesBefore = minutes
                return .none

            // MARK: - Edit existing event

            case .openForEditingEvent(let id):
                state.mode = .edit(id)
                // An existing event is always a calendar event; lock
                // the destination so the user can't accidentally
                // dispatch a calendar event to mail or reminders.
                // (Stage C will hide the tab strip in edit mode; for
                // now the lock is just state-level.)
                state.destination = .calendar
                return .run { send in
                    do {
                        guard let draft = try await eventKit.fetchEventDraft(id) else {
                            await send(.editingEventLoadFailed(
                                AppStrings.DispatchModal.editLoadEventNotFound
                            ))
                            return
                        }
                        await send(.editingEventLoaded(draft))
                    } catch {
                        await send(.editingEventLoadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: "dispatchLoadEditingEvent", cancelInFlight: true)

            case .editingEventLoaded(let draft):
                // Pour the draft into state. The view re-renders from
                // these flat fields without caring that they arrived
                // from a fetch vs. user typing.
                if state.tasks.indices.contains(state.currentIndex) {
                    state.tasks[state.currentIndex].line = draft.title
                }
                state.note = draft.notes
                state.calendarStart = draft.startDate
                state.calendarEnd = draft.endDate
                state.eventLocation = draft.location
                state.eventLocationCoordinate = draft.locationCoordinate
                state.eventURL = draft.url?.absoluteString ?? ""
                state.eventCalendarID = draft.calendarID
                state.eventRecurrence = draft.recurrence
                // v1 surfaces a single alarm. If the saved event had
                // multiple, we show the first and silently drop the
                // rest on save — same trade-off Apple Calendar's
                // quick-edit makes.
                state.eventAlarmMinutesBefore = draft.alarmsMinutesBefore.first
                return .none

            case .editingEventLoadFailed(let message):
                // Reuse the existing failure UI (banner from `saveState
                // == .failed`). The user can cancel and retry; for
                // v1 we don't surface a separate "load failed" state.
                state.saveState = .failed(message)
                return .none

            case .eventLocationChanged(let text):
                state.eventLocation = text
                // Typing invalidates any previously-resolved coordinate
                // — the suggestion the user tapped no longer matches
                // what's in the field.
                state.eventLocationCoordinate = nil
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    state.locationSuggestions = []
                    // Tear down any in-flight stream so a late yield
                    // can't repopulate the list after the user cleared.
                    return .cancel(id: "locationSuggestionsStream")
                }
                return .run { send in
                    for await suggestions in locationSearch.suggestions(trimmed) {
                        await send(.locationSuggestionsUpdated(suggestions))
                    }
                }
                .cancellable(id: "locationSuggestionsStream", cancelInFlight: true)

            case .locationSuggestionsUpdated(let suggestions):
                state.locationSuggestions = IdentifiedArray(uniqueElements: suggestions)
                return .none

            case .locationSuggestionTapped(let suggestion):
                // Optimistic: the tapped title fills the field
                // immediately so the user doesn't see an empty input
                // while we resolve to a coordinate. We don't overwrite
                // with `resolved.title` later — that's usually the same
                // string anyway, and overwriting would briefly flash
                // the text if MapKit returns a slight variant.
                state.eventLocation = suggestion.title
                state.locationSuggestions = []
                return .run { send in
                    do {
                        let resolved = try await locationSearch.resolve(suggestion)
                        await send(.locationResolved(resolved))
                    } catch {
                        await send(.locationResolveFailed)
                    }
                }
                .cancellable(id: "locationResolve", cancelInFlight: true)

            case .locationResolved(let resolved):
                state.eventLocationCoordinate = LocationCoordinate(
                    latitude: resolved.latitude,
                    longitude: resolved.longitude
                )
                return .none

            case .locationResolveFailed:
                // Keep the optimistic text but no coordinate. The event
                // saves as a string-only location — same outcome as
                // hand-typing into Apple Calendar without picking a
                // suggestion. No error UI: a failure here means
                // "Calendar.app won't show a map preview", which is
                // recoverable and not worth interrupting the user for.
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
                let calendarStart = state.calendarStart ?? cal.now()
                let calendarEnd = state.calendarEnd
                    ?? calendarStart.addingTimeInterval(State.defaultEventDuration)
                let eventCalendarID = state.eventCalendarID
                let reminderListID = state.reminderListID
                let reminderDue = state.reminderDue
                let reminderHasTime = state.reminderHasTime
                let mailTo = state.mailTo
                let mailSubject = state.effectiveMailSubject
                // Trim → parse → require a scheme. Empty / whitespace-only
                // input maps to `nil` from URL(string:). Schemeless input
                // like "example.com" technically parses (as a relative URL)
                // but Calendar.app can't make it tappable, so we drop it.
                // Apple Calendar's URL field has the same outward behavior:
                // accepts free text, only saves what it can render.
                let trimmedURL = state.eventURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let eventURL = URL(string: trimmedURL).flatMap { $0.scheme == nil ? nil : $0 }
                let eventLocation = state.eventLocation
                let eventLocationCoordinate = state.eventLocationCoordinate
                let eventRecurrence = state.eventRecurrence
                let alarms: [Int] = state.eventAlarmMinutesBefore.map { [$0] } ?? []
                let mode = state.mode

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
                                location: eventLocation,
                                locationCoordinate: eventLocationCoordinate,
                                url: eventURL,
                                calendarID: eventCalendarID,
                                alarmsMinutesBefore: alarms,
                                recurrence: eventRecurrence
                            )
                            let id: EventKitIdentifier
                            switch mode {
                            case .edit(let existingID):
                                try await eventKit.updateEvent(existingID, draft)
                                id = existingID
                            case .create:
                                id = try await eventKit.createEvent(draft)
                            }
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
                // Lazy seed of calendar start/end. Default start is
                // `now` — today, current moment. The user picks a
                // specific time via the Time field if they want; we
                // don't pre-anchor to tomorrow or to a rounded hour.
                // calendarEnd defaults to start + defaultEventDuration
                // and follows start unless the user explicitly edits
                // the end fields.
                if state.calendarStart == nil {
                    state.calendarStart = cal.now()
                }
                if state.calendarEnd == nil, let start = state.calendarStart {
                    state.calendarEnd = start.addingTimeInterval(State.defaultEventDuration)
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

/// Move `calendarStart` to `newStart` while preserving the current
/// `(end − start)` interval. Mirrors Apple Calendar: dragging the start
/// time slides the end with it, so the event duration stays fixed
/// unless the user explicitly edits the End fields. If either side of
/// the existing interval is nil (pre-seed edge case), fall back to the
/// default duration. Floors at `minEventDuration` so a degenerate
/// `end <= start` state self-heals on the next start edit.
private func shiftCalendarStart(in state: inout DispatchFeature.State, to newStart: Date) {
    let duration: TimeInterval
    if let oldStart = state.calendarStart, let oldEnd = state.calendarEnd {
        duration = oldEnd.timeIntervalSince(oldStart)
    } else {
        duration = DispatchFeature.State.defaultEventDuration
    }
    let safe = max(DispatchFeature.State.minEventDuration, duration)
    state.calendarStart = newStart
    state.calendarEnd = newStart.addingTimeInterval(safe)
}

/// Enforce `end >= start + minEventDuration`. EKEvent rejects
/// `end <= start`; this is the gate that keeps direct end-field edits
/// inside that constraint. The picker is bound to `state.calendarEnd`,
/// so the user briefly sees their pick then watches it snap into a
/// valid range — that bounce is intentional UX (matches Apple Calendar),
/// not a rendering bug to "fix" by removing the clamp.
///
/// `start == nil` is the pre-seed edge case; we pass `end` through
/// without enforcement so onAppear's seed produces a coherent state on
/// the next tick.
private func clampEndAfterStart(end: Date, start: Date?) -> Date {
    guard let start else { return end }
    return max(end, start.addingTimeInterval(DispatchFeature.State.minEventDuration))
}

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

/// Combine the y/m/d of one Date with the hour/minute of another, in
/// the user's calendar. Used to keep Date and Time as independently
/// editable fields even though they share a single Date storage on
/// State. Takes `CalendarContext` (not raw `Calendar`) so the user's
/// calendar is resolved at the helper boundary — every caller passes
/// the same `cal`, and extracting + reconstructing in the SAME
/// `Calendar` instance avoids the off-by-one trap called out in the
/// dates EDD.
private func mergedDate(datePart: Date, timePart: Date, cal: CalendarContext) -> Date {
    let userCal = cal.userCalendar()
    let dateComponents = userCal.dateComponents([.year, .month, .day], from: datePart)
    let timeComponents = userCal.dateComponents([.hour, .minute], from: timePart)
    var merged = DateComponents()
    merged.year = dateComponents.year
    merged.month = dateComponents.month
    merged.day = dateComponents.day
    merged.hour = timeComponents.hour
    merged.minute = timeComponents.minute
    return userCal.date(from: merged) ?? datePart
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
