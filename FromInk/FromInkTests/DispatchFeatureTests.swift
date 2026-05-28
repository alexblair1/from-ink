import ComposableArchitecture
import XCTest
@testable import FromInk

@MainActor
final class DispatchFeatureTests: XCTestCase {

    // Fixed clock used across the file. 2026-05-27 14:00 UTC is a normal
    // weekday afternoon — not a DST boundary, not a year/month edge.
    private static let fixedNow = Date(timeIntervalSince1970: 1_779_624_000)

    /// Bridges `CalendarContext.fixed` (deterministic clock) and a fully-
    /// stubbed `EventKitService` so every test gets a clean dependency
    /// set without having to repeat the boilerplate.
    private func makeStore(
        tasks: [DispatchTask] = [.init(line: "Send Alex the Q2 OKR draft")],
        eventAuth: PermissionAuthStatus = .fullAccess,
        reminderAuth: PermissionAuthStatus = .fullAccess,
        calendars: [CalendarSnapshot] = [
            .init(id: "cal-1", title: "Work", colorHex: "#000000FF",
                  isWritable: true, sourceTitle: "iCloud")
        ],
        reminderLists: [ReminderListSnapshot] = [
            .init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)
        ],
        createEvent: @escaping @Sendable (DraftEvent) async throws -> EventKitIdentifier
            = { _ in "event-id" },
        createReminder: @escaping @Sendable (DraftReminder) async throws -> EventKitIdentifier
            = { _ in "reminder-id" }
    ) -> TestStore<DispatchFeature.State, DispatchFeature.Action> {
        let stubbedEK = EventKitService(
            fetchTodayEvents: { [] },
            fetchDueReminders: { [] },
            fetchEvents: { _ in [] },
            fetchReminders: { _ in [] },
            eventAuthStatus: { eventAuth },
            reminderAuthStatus: { reminderAuth },
            requestEventAccess: { eventAuth },
            requestReminderAccess: { reminderAuth },
            listCalendars: { calendars },
            listReminderLists: { reminderLists },
            createEvent: createEvent,
            updateEvent: { _, _ in },
            createReminder: createReminder,
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in }
        )

        return TestStore(
            initialState: DispatchFeature.State(tasks: tasks),
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubbedEK
                // Belt-and-braces — the fixed calendar context doesn't
                // touch `\.date`, but if `liveValue` ever gets resolved
                // (e.g. via host-app side effects at test launch) it
                // reads `@Dependency(\.date)`. Pin the clock here too.
                $0.date = .constant(Self.fixedNow)
            }
        )
    }

    // MARK: - Lifecycle

    func test_onAppear_seedsCalendarStartToNow_andLoadsCalendarsAndLists() async {
        let store = makeStore()

        // The reducer seeds `calendarStart` inline before returning the
        // auth-read effect, so the mutation lands on .onAppear itself.
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        // Auth status reads are synchronous fullAccess in this stub.
        await store.receive(.authStatusesResolved(
            calendar: .fullAccess,
            reminder: .fullAccess
        )) {
            $0.calendarAuth = .fullAccess
            $0.reminderAuth = .fullAccess
        }
        // The two list loads fire concurrently via `.merge`. TestStore
        // accepts them in any order, but we have to receive both.
        await store.receive(.reminderListsLoaded([
            .init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)
        ])) {
            $0.reminderLists = [.init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)]
            $0.reminderListID = "list-1"
        }
        await store.receive(.eventCalendarsLoaded([
            .init(id: "cal-1", title: "Work", colorHex: "#000000FF", isWritable: true, sourceTitle: "iCloud")
        ])) {
            $0.eventCalendars = [.init(id: "cal-1", title: "Work", colorHex: "#000000FF", isWritable: true, sourceTitle: "iCloud")]
            $0.eventCalendarID = "cal-1"
        }
    }

    func test_onAppear_seedsCalendarStartFromCalendarContext() async {
        let store = makeStore()

        // The seed happens inline in `.onAppear` before the effect runs.
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        // Drain follow-up effects.
        await store.skipReceivedActions()
    }

    func test_onAppear_doesNotReseedExistingCalendarStart() async {
        let existing = Date(timeIntervalSince1970: 1_700_000_000)
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.calendarStart = existing

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubEventKit()
                $0.date = .constant(Self.fixedNow)
            }
        )

        // calendarStart is not the .distantPast sentinel, so .onAppear
        // must leave it alone — the user may have already adjusted it.
        await store.send(.onAppear)
        await store.skipReceivedActions()
        XCTAssertEqual(store.state.calendarStart, existing)
    }

    // MARK: - Line editing

    func test_lineChanged_updatesCurrentTaskLine() async {
        let store = makeStore(tasks: [.init(line: "original")])

        await store.send(.lineChanged("edited")) {
            $0.tasks[0].line = "edited"
        }
    }

    func test_editingChanged_togglesEditorState() async {
        let store = makeStore()

        await store.send(.editingChanged(true)) {
            $0.isEditingLine = true
        }
        await store.send(.editingChanged(false)) {
            $0.isEditingLine = false
        }
    }

    // MARK: - Date / time merge

    func test_calendarDateChanged_preservesTimeComponent() async {
        // Seed at 2026-05-27 14:00 in America/New_York (fixed context's
        // calendar). Then "pick" 2026-06-15 in the date picker — the
        // time-of-day should stay 14:00 in the user calendar, not get
        // stomped to midnight.
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow  // 14:00 UTC = 10:00 EDT
        }
        await store.skipReceivedActions()

        let newDate = Date(timeIntervalSince1970: 1_781_000_000)  // 2026-06-09 14:13 UTC
        await store.send(.calendarDateChanged(newDate)) { state in
            let cal = CalendarContext.fixed(now: Self.fixedNow).userCalendar()
            // Date part comes from `newDate`, time part from existing.
            let expected = cal.date(from: DateComponents(
                year: cal.component(.year, from: newDate),
                month: cal.component(.month, from: newDate),
                day: cal.component(.day, from: newDate),
                hour: cal.component(.hour, from: Self.fixedNow),
                minute: cal.component(.minute, from: Self.fixedNow)
            ))!
            state.calendarStart = expected
        }
    }

    func test_calendarTimeChanged_preservesDateComponent() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        await store.skipReceivedActions()

        // A different time on a different day — only h/m should transfer.
        let newTime = Date(timeIntervalSince1970: 1_700_000_000)  // arbitrary
        await store.send(.calendarTimeChanged(newTime)) { state in
            let cal = CalendarContext.fixed(now: Self.fixedNow).userCalendar()
            let expected = cal.date(from: DateComponents(
                year: cal.component(.year, from: Self.fixedNow),
                month: cal.component(.month, from: Self.fixedNow),
                day: cal.component(.day, from: Self.fixedNow),
                hour: cal.component(.hour, from: newTime),
                minute: cal.component(.minute, from: newTime)
            ))!
            state.calendarStart = expected
        }
    }

    // MARK: - Destination switching

    func test_destinationSelected_preservesFieldsAcrossSwitch() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        await store.skipReceivedActions()

        // Type a mail recipient on the Mail destination …
        await store.send(.destinationSelected(.mail)) {
            $0.destination = .mail
        }
        await store.send(.mailToChanged("alex@example.com")) {
            $0.mailTo = "alex@example.com"
        }
        // … switch to Calendar …
        await store.send(.destinationSelected(.calendar)) {
            $0.destination = .calendar
        }
        // … and back. The mail recipient must survive.
        await store.send(.destinationSelected(.mail)) {
            $0.destination = .mail
        }
        XCTAssertEqual(store.state.mailTo, "alex@example.com")
    }

    // MARK: - Permission gating

    func test_canSend_isFalse_whenPermissionUndetermined() async {
        let store = makeStore(eventAuth: .notDetermined)
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        await store.receive(.authStatusesResolved(
            calendar: .notDetermined,
            reminder: .fullAccess
        )) {
            $0.calendarAuth = .notDetermined
            $0.reminderAuth = .fullAccess
        }
        await store.receive(.reminderListsLoaded([
            .init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)
        ])) {
            $0.reminderLists = [.init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)]
            $0.reminderListID = "list-1"
        }
        XCTAssertFalse(store.state.canSend)
    }

    /// Synthetic state already past `.onAppear` — calendar auth needs
    /// granting, reminders already denied (so no reminder-list noise).
    /// Tests the core invariant: when the user grants Calendar, the
    /// reducer flips `calendarAuth` and fires the deferred calendar
    /// list load.
    func test_permissionResolved_calendar_fullAccess_triggersCalendarListLoad() async {
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.calendarAuth = .notDetermined
        state.reminderAuth = .denied  // suppress reminder-list effect

        let calendar = CalendarSnapshot(
            id: "cal-1", title: "Work", colorHex: "#000000FF",
            isWritable: true, sourceTitle: "iCloud"
        )
        let stubbedEK = EventKitService(
            fetchTodayEvents: { [] },
            fetchDueReminders: { [] },
            fetchEvents: { _ in [] },
            fetchReminders: { _ in [] },
            eventAuthStatus: { .fullAccess },
            reminderAuthStatus: { .denied },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .denied },
            listCalendars: { [calendar] },
            listReminderLists: { [] },
            createEvent: { _ in "event-id" },
            updateEvent: { _, _ in },
            createReminder: { _ in "reminder-id" },
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in }
        )

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubbedEK
                // Belt-and-braces — the fixed calendar context doesn't
                // touch `\.date`, but if `liveValue` ever gets resolved
                // (e.g. via host-app side effects at test launch) it
                // reads `@Dependency(\.date)`. Pin the clock here too.
                $0.date = .constant(Self.fixedNow)
            }
        )

        // Directly drive the resolution action that the request effect
        // would have produced — skips the prompt round-trip and the
        // `.onAppear` boilerplate.
        await store.send(.permissionResolved(.calendar, .fullAccess)) {
            $0.calendarAuth = .fullAccess
        }
        await store.receive(.eventCalendarsLoaded([calendar])) {
            $0.eventCalendars = [calendar]
            $0.eventCalendarID = "cal-1"
        }
    }

    /// `.allowAccessTapped` on a not-yet-determined Calendar destination
    /// runs the request effect and forwards the resolved status into
    /// `permissionResolved`. We deliberately don't assert the list load
    /// here — that's covered above; this test only verifies the request
    /// pathway.
    func test_allowAccessTapped_calendar_runsRequestEffect() async {
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.calendarAuth = .notDetermined
        state.reminderAuth = .denied

        let stubbedEK = EventKitService(
            fetchTodayEvents: { [] },
            fetchDueReminders: { [] },
            fetchEvents: { _ in [] },
            fetchReminders: { _ in [] },
            eventAuthStatus: { .notDetermined },
            reminderAuthStatus: { .denied },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .denied },
            listCalendars: { [] },  // empty → no effect from list load
            listReminderLists: { [] },
            createEvent: { _ in "event-id" },
            updateEvent: { _, _ in },
            createReminder: { _ in "reminder-id" },
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in }
        )

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubbedEK
                // Belt-and-braces — the fixed calendar context doesn't
                // touch `\.date`, but if `liveValue` ever gets resolved
                // (e.g. via host-app side effects at test launch) it
                // reads `@Dependency(\.date)`. Pin the clock here too.
                $0.date = .constant(Self.fixedNow)
            }
        )

        await store.send(.allowAccessTapped)
        await store.receive(.permissionResolved(.calendar, .fullAccess)) {
            $0.calendarAuth = .fullAccess
        }
        // Calendar list load still fires from permissionResolved →
        // empty list → empty mutation. Drain it.
        await store.receive(.eventCalendarsLoaded([]))
    }

    // MARK: - Send happy path

    func test_sendTapped_calendar_createsEvent_andCompletes() async {
        let savedTitle = LockIsolated<String?>(nil)
        let savedCalendarID = LockIsolated<String?>(nil)

        let store = makeStore(
            tasks: [.init(line: "Submit Q2 report")],
            createEvent: { draft in
                savedTitle.setValue(draft.title)
                savedCalendarID.setValue(draft.calendarID)
                return "event-42"
            }
        )

        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        await store.receive(.authStatusesResolved(
            calendar: .fullAccess,
            reminder: .fullAccess
        )) {
            $0.calendarAuth = .fullAccess
            $0.reminderAuth = .fullAccess
        }
        await store.receive(.reminderListsLoaded([
            .init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)
        ])) {
            $0.reminderLists = [.init(id: "list-1", title: "Inbox", colorHex: "#000000FF", isWritable: true)]
            $0.reminderListID = "list-1"
        }
        await store.receive(.eventCalendarsLoaded([
            .init(id: "cal-1", title: "Work", colorHex: "#000000FF", isWritable: true, sourceTitle: "iCloud")
        ])) {
            $0.eventCalendars = [.init(id: "cal-1", title: "Work", colorHex: "#000000FF", isWritable: true, sourceTitle: "iCloud")]
            $0.eventCalendarID = "cal-1"
        }

        await store.send(.sendTapped) {
            $0.saveState = .saving
        }
        await store.receive(.sendCompleted("event-42")) {
            $0.saveState = .idle
            $0.resolved[$0.tasks[0].id] = .sent
            $0.completion = .finished
        }

        XCTAssertEqual(savedTitle.value, "Submit Q2 report")
        XCTAssertEqual(savedCalendarID.value, "cal-1")
    }

    // MARK: - Send failure path

    func test_sendTapped_failure_surfacesErrorMessage() async {
        struct TestError: LocalizedError {
            var errorDescription: String? { "calendar unavailable" }
        }

        let store = makeStore(
            createEvent: { _ in throw TestError() }
        )

        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
        }
        await store.skipReceivedActions()

        await store.send(.sendTapped) {
            $0.saveState = .saving
        }
        await store.receive(.sendFailed("calendar unavailable")) {
            $0.saveState = .failed("calendar unavailable")
        }
        // Completion is NOT set on failure — the user can retry.
        XCTAssertNil(store.state.completion)
    }

    // MARK: - Stack navigation

    func test_skipTapped_advancesToNextTask() async {
        let t1 = DispatchTask(line: "first")
        let t2 = DispatchTask(line: "second")
        let store = makeStore(tasks: [t1, t2])

        await store.send(.skipTapped) {
            $0.resolved[t1.id] = .skipped
            $0.currentIndex = 1
        }
    }

    func test_skipTapped_onLastTask_marksFinished() async {
        let only = DispatchTask(line: "only")
        let store = makeStore(tasks: [only])

        await store.send(.skipTapped) {
            $0.resolved[only.id] = .skipped
            $0.completion = .finished
        }
    }

    func test_nextTaskTapped_advancesAndResetsEditing() async {
        let t1 = DispatchTask(line: "first")
        let t2 = DispatchTask(line: "second")
        var state = DispatchFeature.State(tasks: [t1, t2])
        state.isEditingLine = true

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubEventKit()
                $0.date = .constant(Self.fixedNow)
            }
        )

        await store.send(.nextTaskTapped) {
            $0.currentIndex = 1
            $0.isEditingLine = false
        }
    }

    func test_nextTaskTapped_atEnd_isNoOp() async {
        let only = DispatchTask(line: "only")
        let store = makeStore(tasks: [only])

        await store.send(.nextTaskTapped)
    }

    // MARK: - Cancel

    func test_cancelTapped_setsCompletionCancelled() async {
        let store = makeStore()

        await store.send(.cancelTapped) {
            $0.completion = .cancelled
        }
    }

    // MARK: - Picker overlay

    func test_overlayOpened_andDismissed() async {
        let store = makeStore()

        await store.send(.overlayOpened(.calendarDate)) {
            $0.openOverlay = .calendarDate
        }
        await store.send(.overlayDismissed) {
            $0.openOverlay = nil
        }
    }

    // MARK: - Reminder due-date interaction

    func test_dueDateChanged_toNil_clearsHasTime() async {
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.reminderDue = Self.fixedNow
        state.reminderHasTime = true

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubEventKit()
                $0.date = .constant(Self.fixedNow)
            }
        )

        await store.send(.reminderDueChanged(nil)) {
            $0.reminderDue = nil
            $0.reminderHasTime = false
        }
    }

    // MARK: - Helpers

    private func stubEventKit() -> EventKitService {
        EventKitService(
            fetchTodayEvents: { [] },
            fetchDueReminders: { [] },
            fetchEvents: { _ in [] },
            fetchReminders: { _ in [] },
            eventAuthStatus: { .fullAccess },
            reminderAuthStatus: { .fullAccess },
            requestEventAccess: { .fullAccess },
            requestReminderAccess: { .fullAccess },
            listCalendars: { [] },
            listReminderLists: { [] },
            createEvent: { _ in "event-id" },
            updateEvent: { _, _ in },
            createReminder: { _ in "reminder-id" },
            updateReminder: { _, _ in },
            fetchEventDraft: { _ in nil },
            fetchReminderDraft: { _ in nil },
            deleteEvent: { _ in },
            deleteReminder: { _ in }
        )
    }
}
