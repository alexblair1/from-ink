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
            = { _ in "reminder-id" },
        locationSuggestions: @escaping @Sendable (String) -> AsyncStream<[LocationSuggestion]>
            = { _ in AsyncStream { $0.finish() } },
        locationResolve: @escaping @Sendable (LocationSuggestion) async throws -> ResolvedLocation
            = { _ in ResolvedLocation(
                title: "Apple Park",
                address: "1 Apple Park Way, Cupertino, CA",
                latitude: 37.3349, longitude: -122.0090
            ) }
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
                $0.locationSearchService = LocationSearchService(
                    suggestions: locationSuggestions,
                    resolve: locationResolve
                )
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

        // The reducer seeds `calendarStart` AND `calendarEnd` inline
        // before returning the auth-read effect, so the mutations land
        // on .onAppear itself. End defaults to start + 30 min.
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        // Drain follow-up effects.
        await store.skipReceivedActions()
    }

    func test_onAppear_doesNotReseedExistingCalendarStart() async {
        let existing = Date(timeIntervalSince1970: 1_700_000_000)
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.calendarStart = existing
        state.calendarEnd = existing.addingTimeInterval(3600)

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
        // must leave both it and calendarEnd alone — the user may have
        // already adjusted them.
        await store.send(.onAppear)
        await store.skipReceivedActions()
        XCTAssertEqual(store.state.calendarStart, existing)
        XCTAssertEqual(store.state.calendarEnd, existing.addingTimeInterval(3600))
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
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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
            // End slides by the same delta — preserves the (end − start)
            // duration that the seed set (defaultEventDuration here, but
            // see `test_calendarStartChanged_preservesArbitraryDuration`
            // for the general invariant).
            state.calendarEnd = expected.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
    }

    func test_calendarTimeChanged_preservesDateComponent() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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
            state.calendarEnd = expected.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
    }

    func test_calendarStartChanged_preservesArbitraryDuration() async {
        // Synthetic state with a 2-hour (not 30-min) event. The
        // duration-preserving guarantee should hold for whatever
        // duration the user chose, not just the default.
        let start = Self.fixedNow
        let end = start.addingTimeInterval(7200)  // 2 hours
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.calendarStart = start
        state.calendarEnd = end

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubEventKit()
                $0.date = .constant(Self.fixedNow)
            }
        )

        // Move start forward 3 hours. End must slide forward 3 hours
        // too — 2-hour interval preserved.
        let newStart = start.addingTimeInterval(10_800)
        await store.send(.calendarTimeChanged(newStart)) { newState in
            let cal = CalendarContext.fixed(now: Self.fixedNow).userCalendar()
            let merged = cal.date(from: DateComponents(
                year: cal.component(.year, from: start),
                month: cal.component(.month, from: start),
                day: cal.component(.day, from: start),
                hour: cal.component(.hour, from: newStart),
                minute: cal.component(.minute, from: newStart)
            ))!
            newState.calendarStart = merged
            newState.calendarEnd = merged.addingTimeInterval(7200)
        }
    }

    func test_calendarEndDateChanged_swapsDate_preservesEndTime() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        // Pick a different day; end TIME (h:m) must survive intact.
        let newDate = Date(timeIntervalSince1970: 1_781_000_000)
        await store.send(.calendarEndDateChanged(newDate)) { state in
            let cal = CalendarContext.fixed(now: Self.fixedNow).userCalendar()
            let priorEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
            let expected = cal.date(from: DateComponents(
                year: cal.component(.year, from: newDate),
                month: cal.component(.month, from: newDate),
                day: cal.component(.day, from: newDate),
                hour: cal.component(.hour, from: priorEnd),
                minute: cal.component(.minute, from: priorEnd)
            ))!
            state.calendarEnd = expected
        }
    }

    func test_calendarEndTimeChanged_swapsTime_preservesEndDate() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        // Different day, different hour — only h:m should land on end.
        let newTime = Date(timeIntervalSince1970: 1_700_000_000)
        await store.send(.calendarEndTimeChanged(newTime)) { state in
            let cal = CalendarContext.fixed(now: Self.fixedNow).userCalendar()
            let priorEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
            let expected = cal.date(from: DateComponents(
                year: cal.component(.year, from: priorEnd),
                month: cal.component(.month, from: priorEnd),
                day: cal.component(.day, from: priorEnd),
                hour: cal.component(.hour, from: newTime),
                minute: cal.component(.minute, from: newTime)
            ))!
            state.calendarEnd = expected
        }
    }

    func test_calendarEndDateChanged_beforeStart_clampsToStartPlusMin() async {
        // User picks an end date BEFORE start. Reducer clamps to
        // start + minEventDuration so EKEvent's `end > start`
        // invariant is preserved.
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        let oneYearBefore = Self.fixedNow.addingTimeInterval(-365 * 86400)
        await store.send(.calendarEndDateChanged(oneYearBefore)) { state in
            state.calendarEnd = Self.fixedNow
                .addingTimeInterval(DispatchFeature.State.minEventDuration)
        }
    }

    func test_calendarTimeChanged_recoversFromDegenerateEnd_atMinFloor() async {
        // Degenerate input state: end already lies BEFORE start (someone
        // poked at an Optional in the wrong order, a migration loaded
        // bad rows, etc.). The reducer's shiftCalendarStart helper
        // floors the preserved duration at minEventDuration so the next
        // start edit self-heals the invariant rather than carrying the
        // negative duration forward.
        let start = Self.fixedNow
        let badEnd = start.addingTimeInterval(-3600)  // end 1hr BEFORE start
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.calendarStart = start
        state.calendarEnd = badEnd

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = stubEventKit()
                $0.date = .constant(Self.fixedNow)
            }
        )

        // Shift start by editing the time; the preserved duration is
        // negative, so the floor kicks in.
        let newTime = start.addingTimeInterval(3600)
        await store.send(.calendarTimeChanged(newTime)) { newState in
            let cal = CalendarContext.fixed(now: Self.fixedNow).userCalendar()
            let merged = cal.date(from: DateComponents(
                year: cal.component(.year, from: start),
                month: cal.component(.month, from: start),
                day: cal.component(.day, from: start),
                hour: cal.component(.hour, from: newTime),
                minute: cal.component(.minute, from: newTime)
            ))!
            newState.calendarStart = merged
            newState.calendarEnd = merged
                .addingTimeInterval(DispatchFeature.State.minEventDuration)
        }
    }

    // MARK: - Destination switching

    func test_destinationSelected_preservesFieldsAcrossSwitch() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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

    // MARK: - Event URL field

    func test_eventURLChanged_updatesState() async {
        let store = makeStore()
        await store.send(.eventURLChanged("https://example.com")) {
            $0.eventURL = "https://example.com"
        }
    }

    func test_destinationSelected_preservesEventURLAcrossSwitch() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        await store.send(.eventURLChanged("https://meet.example.com/abc")) {
            $0.eventURL = "https://meet.example.com/abc"
        }
        // calendar → mail → calendar. URL must survive both switches.
        await store.send(.destinationSelected(.mail)) { $0.destination = .mail }
        await store.send(.destinationSelected(.calendar)) { $0.destination = .calendar }
        XCTAssertEqual(store.state.eventURL, "https://meet.example.com/abc")
    }

    func test_sendTapped_calendar_passesValidURL_toDraftEvent() async {
        let savedURL = LockIsolated<URL?>(nil)
        let store = makeStore(
            createEvent: { draft in
                savedURL.setValue(draft.url)
                return "event-1"
            }
        )
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        await store.send(.eventURLChanged("https://meet.example.com/abc")) {
            $0.eventURL = "https://meet.example.com/abc"
        }
        await store.send(.sendTapped) {
            $0.saveState = .saving
        }
        await store.receive(.sendCompleted("event-1")) {
            $0.saveState = .idle
            $0.resolved[$0.tasks[0].id] = .sent
            $0.completion = .finished
        }
        XCTAssertEqual(savedURL.value, URL(string: "https://meet.example.com/abc"))
    }

    func test_sendTapped_calendar_dropsWhitespaceOnlyURL() async {
        // URL(string: "") returns nil. After trimming, whitespace-only
        // input also lands at empty → nil. Most common "drop me" case.
        let savedURL = LockIsolated<URL?>(URL(string: "https://placeholder"))
        let store = makeStore(
            createEvent: { draft in
                savedURL.setValue(draft.url)
                return "event-1"
            }
        )
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        await store.send(.eventURLChanged("   ")) { $0.eventURL = "   " }
        await store.send(.sendTapped) { $0.saveState = .saving }
        await store.receive(.sendCompleted("event-1")) {
            $0.saveState = .idle
            $0.resolved[$0.tasks[0].id] = .sent
            $0.completion = .finished
        }
        XCTAssertNil(savedURL.value)
    }

    // MARK: - Event location field

    func test_eventLocationChanged_empty_clearsSuggestionsAndDoesNotStartSearch() async {
        // Seed state with a stale suggestion, then send empty text.
        // Reducer must clear the list synchronously and not start a
        // stream (the cancel doesn't produce a follow-up action).
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.eventLocation = "Apple"
        state.eventLocationCoordinate = LocationCoordinate(latitude: 37, longitude: -122)
        state.locationSuggestions = [LocationSuggestion(id: "1", title: "Apple Park", subtitle: "Cupertino")]

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = EventKitService(
                    fetchTodayEvents: { [] }, fetchDueReminders: { [] },
                    fetchEvents: { _ in [] }, fetchReminders: { _ in [] },
                    eventAuthStatus: { .fullAccess }, reminderAuthStatus: { .fullAccess },
                    requestEventAccess: { .fullAccess }, requestReminderAccess: { .fullAccess },
                    listCalendars: { [] }, listReminderLists: { [] },
                    createEvent: { _ in "event-id" }, updateEvent: { _, _ in },
                    createReminder: { _ in "reminder-id" }, updateReminder: { _, _ in },
                    fetchEventDraft: { _ in nil }, fetchReminderDraft: { _ in nil },
                    deleteEvent: { _ in }, deleteReminder: { _ in }
                )
                $0.locationSearchService = LocationSearchService(
                    suggestions: { _ in AsyncStream { $0.finish() } },
                    resolve: { _ in throw LocationSearchError.notFound }
                )
                $0.date = .constant(Self.fixedNow)
            }
        )

        await store.send(.eventLocationChanged("")) {
            $0.eventLocation = ""
            $0.eventLocationCoordinate = nil
            $0.locationSuggestions = []
        }
    }

    func test_eventLocationChanged_nonEmpty_streamsSuggestionsBack() async {
        let park = LocationSuggestion(id: "park", title: "Apple Park", subtitle: "Cupertino, CA")
        let store = makeStore(
            locationSuggestions: { _ in
                AsyncStream { continuation in
                    continuation.yield([park])
                    continuation.finish()
                }
            }
        )

        await store.send(.eventLocationChanged("Apple")) {
            $0.eventLocation = "Apple"
            $0.eventLocationCoordinate = nil
        }
        await store.receive(.locationSuggestionsUpdated([park])) {
            $0.locationSuggestions = [park]
        }
    }

    func test_eventLocationChanged_clearsCoordinate_whenTypingAfterPick() async {
        // The user had previously picked a suggestion (coord set); they
        // start typing again. The coord must clear because it no longer
        // matches the now-edited text.
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.eventLocation = "Apple Park"
        state.eventLocationCoordinate = LocationCoordinate(latitude: 37.3349, longitude: -122.0090)

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = EventKitService(
                    fetchTodayEvents: { [] }, fetchDueReminders: { [] },
                    fetchEvents: { _ in [] }, fetchReminders: { _ in [] },
                    eventAuthStatus: { .fullAccess }, reminderAuthStatus: { .fullAccess },
                    requestEventAccess: { .fullAccess }, requestReminderAccess: { .fullAccess },
                    listCalendars: { [] }, listReminderLists: { [] },
                    createEvent: { _ in "event-id" }, updateEvent: { _, _ in },
                    createReminder: { _ in "reminder-id" }, updateReminder: { _, _ in },
                    fetchEventDraft: { _ in nil }, fetchReminderDraft: { _ in nil },
                    deleteEvent: { _ in }, deleteReminder: { _ in }
                )
                $0.locationSearchService = LocationSearchService(
                    suggestions: { _ in AsyncStream { $0.finish() } },
                    resolve: { _ in throw LocationSearchError.notFound }
                )
                $0.date = .constant(Self.fixedNow)
            }
        )

        await store.send(.eventLocationChanged("Apple Park2")) {
            $0.eventLocation = "Apple Park2"
            $0.eventLocationCoordinate = nil
        }
    }

    func test_locationSuggestionTapped_setsTextAndResolvesCoordinate() async {
        let park = LocationSuggestion(id: "park", title: "Apple Park", subtitle: "Cupertino, CA")
        let resolved = ResolvedLocation(
            title: "Apple Park",
            address: "1 Apple Park Way, Cupertino, CA",
            latitude: 37.3349, longitude: -122.0090
        )
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.locationSuggestions = [park]

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = EventKitService(
                    fetchTodayEvents: { [] }, fetchDueReminders: { [] },
                    fetchEvents: { _ in [] }, fetchReminders: { _ in [] },
                    eventAuthStatus: { .fullAccess }, reminderAuthStatus: { .fullAccess },
                    requestEventAccess: { .fullAccess }, requestReminderAccess: { .fullAccess },
                    listCalendars: { [] }, listReminderLists: { [] },
                    createEvent: { _ in "event-id" }, updateEvent: { _, _ in },
                    createReminder: { _ in "reminder-id" }, updateReminder: { _, _ in },
                    fetchEventDraft: { _ in nil }, fetchReminderDraft: { _ in nil },
                    deleteEvent: { _ in }, deleteReminder: { _ in }
                )
                $0.locationSearchService = LocationSearchService(
                    suggestions: { _ in AsyncStream { $0.finish() } },
                    resolve: { _ in resolved }
                )
                $0.date = .constant(Self.fixedNow)
            }
        )

        // Optimistic text update happens inline; suggestion list clears.
        await store.send(.locationSuggestionTapped(park)) {
            $0.eventLocation = "Apple Park"
            $0.locationSuggestions = []
        }
        // Resolve completes → coordinate lands; text untouched.
        await store.receive(.locationResolved(resolved)) {
            $0.eventLocationCoordinate = LocationCoordinate(latitude: 37.3349, longitude: -122.0090)
        }
    }

    func test_locationSuggestionTapped_resolveFailure_keepsTextWithNoCoordinate() async {
        let park = LocationSuggestion(id: "park", title: "Apple Park", subtitle: "Cupertino, CA")
        var state = DispatchFeature.State(tasks: [.init(line: "x")])
        state.locationSuggestions = [park]

        let store = TestStore(
            initialState: state,
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.calendarContext = .fixed(now: Self.fixedNow)
                $0.eventKitService = EventKitService(
                    fetchTodayEvents: { [] }, fetchDueReminders: { [] },
                    fetchEvents: { _ in [] }, fetchReminders: { _ in [] },
                    eventAuthStatus: { .fullAccess }, reminderAuthStatus: { .fullAccess },
                    requestEventAccess: { .fullAccess }, requestReminderAccess: { .fullAccess },
                    listCalendars: { [] }, listReminderLists: { [] },
                    createEvent: { _ in "event-id" }, updateEvent: { _, _ in },
                    createReminder: { _ in "reminder-id" }, updateReminder: { _, _ in },
                    fetchEventDraft: { _ in nil }, fetchReminderDraft: { _ in nil },
                    deleteEvent: { _ in }, deleteReminder: { _ in }
                )
                $0.locationSearchService = LocationSearchService(
                    suggestions: { _ in AsyncStream { $0.finish() } },
                    resolve: { _ in throw LocationSearchError.notFound }
                )
                $0.date = .constant(Self.fixedNow)
            }
        )

        await store.send(.locationSuggestionTapped(park)) {
            $0.eventLocation = "Apple Park"
            $0.locationSuggestions = []
        }
        // Failure → no coordinate. Text stays.
        await store.receive(.locationResolveFailed)
        XCTAssertNil(store.state.eventLocationCoordinate)
        XCTAssertEqual(store.state.eventLocation, "Apple Park")
    }

    func test_sendTapped_calendar_passesLocation_andCoordinate_toDraftEvent() async {
        let savedLocation = LockIsolated<String?>(nil)
        let savedCoord = LockIsolated<LocationCoordinate?>(nil)
        let store = makeStore(
            createEvent: { draft in
                savedLocation.setValue(draft.location)
                savedCoord.setValue(draft.locationCoordinate)
                return "event-1"
            }
        )
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        // Type "Apple" → stream yields nothing (default stub) → no
        // follow-up action; no skipReceivedActions needed.
        await store.send(.eventLocationChanged("Apple")) {
            $0.eventLocation = "Apple"
            $0.eventLocationCoordinate = nil
        }
        let park = LocationSuggestion(id: "park", title: "Apple Park", subtitle: "Cupertino, CA")
        // Tap optimistically swaps "Apple" → "Apple Park" (observable
        // mutation), then resolve fills in the coordinate.
        await store.send(.locationSuggestionTapped(park)) {
            $0.eventLocation = "Apple Park"
        }
        await store.receive(.locationResolved(ResolvedLocation(
            title: "Apple Park",
            address: "1 Apple Park Way, Cupertino, CA",
            latitude: 37.3349, longitude: -122.0090
        ))) {
            $0.eventLocationCoordinate = LocationCoordinate(latitude: 37.3349, longitude: -122.0090)
        }

        await store.send(.sendTapped) { $0.saveState = .saving }
        await store.receive(.sendCompleted("event-1")) {
            $0.saveState = .idle
            $0.resolved[$0.tasks[0].id] = .sent
            $0.completion = .finished
        }
        XCTAssertEqual(savedLocation.value, "Apple Park")
        XCTAssertEqual(savedCoord.value, LocationCoordinate(latitude: 37.3349, longitude: -122.0090))
    }

    func test_destinationSelected_preservesLocationAndCoordinateAcrossSwitch() async {
        let store = makeStore()
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        let park = LocationSuggestion(id: "park", title: "Apple Park", subtitle: "Cupertino, CA")
        await store.send(.locationSuggestionTapped(park)) {
            $0.eventLocation = "Apple Park"
            $0.locationSuggestions = []
        }
        await store.receive(.locationResolved(ResolvedLocation(
            title: "Apple Park",
            address: "1 Apple Park Way, Cupertino, CA",
            latitude: 37.3349, longitude: -122.0090
        ))) {
            $0.eventLocationCoordinate = LocationCoordinate(latitude: 37.3349, longitude: -122.0090)
        }

        // calendar → mail → calendar. Both fields survive.
        await store.send(.destinationSelected(.mail)) { $0.destination = .mail }
        await store.send(.destinationSelected(.calendar)) { $0.destination = .calendar }
        XCTAssertEqual(store.state.eventLocation, "Apple Park")
        XCTAssertEqual(
            store.state.eventLocationCoordinate,
            LocationCoordinate(latitude: 37.3349, longitude: -122.0090)
        )
    }

    func test_sendTapped_calendar_dropsSchemelessURL() async {
        // "example.com" without a scheme parses as a RELATIVE URL —
        // URL(string:) returns non-nil — but Calendar.app can't make a
        // schemeless URL tappable. The send-path scheme guard exists
        // precisely so input like this doesn't quietly degrade.
        let savedURL = LockIsolated<URL?>(URL(string: "https://placeholder"))
        let store = makeStore(
            createEvent: { draft in
                savedURL.setValue(draft.url)
                return "event-1"
            }
        )
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
        }
        await store.skipReceivedActions()

        await store.send(.eventURLChanged("example.com")) { $0.eventURL = "example.com" }
        await store.send(.sendTapped) { $0.saveState = .saving }
        await store.receive(.sendCompleted("event-1")) {
            $0.saveState = .idle
            $0.resolved[$0.tasks[0].id] = .sent
            $0.completion = .finished
        }
        XCTAssertNil(savedURL.value)
    }

    // MARK: - Permission gating

    func test_canSend_isFalse_whenPermissionUndetermined() async {
        let store = makeStore(eventAuth: .notDetermined)
        await store.send(.onAppear) {
            $0.calendarStart = Self.fixedNow
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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
            $0.calendarEnd = Self.fixedNow.addingTimeInterval(DispatchFeature.State.defaultEventDuration)
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
