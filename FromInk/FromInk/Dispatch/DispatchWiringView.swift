import ComposableArchitecture
import SwiftUI

struct DispatchWiringView: View {
    let store: StoreOf<DispatchFeature>
    @Dependency(\.calendarContext) private var cal

    var body: some View {
        DispatchView(
            model: .init(store: store, cal: cal),
            line: Binding(
                get: { store.currentLine },
                set: { store.send(.lineChanged($0)) }
            ),
            note: Binding(
                get: { store.note },
                set: { store.send(.noteChanged($0)) }
            )
        )
        .task { store.send(.onAppear) }
    }
}

// MARK: - Adapter

extension DispatchView.Model {
    init(
        store: StoreOf<DispatchFeature>,
        cal: CalendarContext,
        ds: DesignSystem = .standard
    ) {
        let destination = store.destination
        let isGranted = store.currentAuth == .fullAccess

        // Resolve calendar dates once. The reducer seeds on `.onAppear`,
        // but a render in the brief window before the seed lands sees
        // `nil` — fall back to `now` + default duration so the displayed
        // values match what the seed produces moments later.
        let displayStart = store.calendarStart ?? cal.now()
        let displayEnd = store.calendarEnd
            ?? displayStart.addingTimeInterval(DispatchFeature.State.defaultEventDuration)

        // Destination tab strip — reuses InkTabStrip (the home-screen
        // tab pattern). Identifiers are the Destination raw values so
        // the strip stays decoupled from the reducer's enum.
        let destinationChips: [InkTabStrip<String>.Tab] = [
            .init(
                id: DispatchFeature.State.Destination.calendar.rawValue,
                iconName: "calendar",
                label: AppStrings.DispatchModal.calendar,
                isActive: destination == .calendar
            ),
            .init(
                id: DispatchFeature.State.Destination.reminders.rawValue,
                iconName: "checklist",
                label: AppStrings.DispatchModal.reminders,
                isActive: destination == .reminders
            ),
            .init(
                id: DispatchFeature.State.Destination.mail.rawValue,
                iconName: "envelope",
                label: AppStrings.DispatchModal.mail,
                isActive: destination == .mail
            ),
        ]
        let destinationTabModel = InkTabStrip<String>.Model.standard(
            tabs: destinationChips,
            showsLabel: true,
            onTabTapped: { raw in
                if let dest = DispatchFeature.State.Destination(rawValue: raw) {
                    store.send(.destinationSelected(dest))
                }
            }
        )

        // Eyebrow text — switches between single-mode "DISPATCH · 1 LINE"
        // and stack-mode "TASKS · 2 / 4".
        let eyebrowTitle = store.isStack
            ? AppStrings.DispatchModal.titleTasks
            : AppStrings.DispatchModal.titleDispatch
        let eyebrowSubtitle = store.isStack
            ? "\(store.currentIndex + 1) / \(store.tasks.count)"
            : "1 line"

        // Stack-mode progress marks.
        let progress: [DispatchView.Model.ProgressMark] = store.tasks.map { task in
            switch store.resolved[task.id] {
            case .sent:    return .sent
            case .skipped: return .skipped
            case .none:    return .pending
            }
        }

        // Destination-aware fields. Calendar today renders a Date+Time
        // pair plus a full-width Calendar selector; Reminders is a
        // List+Due pair; Mail is a To+Subject pair of inline text
        // fields. Stage 3 grows the Calendar set; the row-array shape
        // accommodates whatever each destination needs.
        let fields: [DispatchView.Model.FieldRow]
        switch destination {
        case .calendar:
            let date = DispatchView.Model.Field(
                kind: .date,
                label: AppStrings.DispatchModal.date,
                value: Self.dateOnlyDisplay(displayStart, cal: cal),
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.calendarDate)) })
                    : .disabledPicker
            )
            let time = DispatchView.Model.Field(
                kind: .time,
                label: AppStrings.DispatchModal.time,
                value: Self.timeOnlyDisplay(displayStart, cal: cal),
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.calendarTime)) })
                    : .disabledPicker
            )
            let endDate = DispatchView.Model.Field(
                kind: .endDate,
                label: AppStrings.DispatchModal.endDate,
                value: Self.dateOnlyDisplay(displayEnd, cal: cal),
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.calendarEndDate)) })
                    : .disabledPicker
            )
            let endTime = DispatchView.Model.Field(
                kind: .endTime,
                label: AppStrings.DispatchModal.endTime,
                value: Self.timeOnlyDisplay(displayEnd, cal: cal),
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.calendarEndTime)) })
                    : .disabledPicker
            )
            let selectedCalendarTitle = store.eventCalendarID.flatMap { id in
                store.eventCalendars[id: id]?.title
            } ?? store.eventCalendars.first?.title ?? ""
            let calendarField = DispatchView.Model.Field(
                kind: .eventCalendar,
                label: AppStrings.DispatchModal.calendar,
                value: selectedCalendarTitle,
                placeholder: "",
                behavior: isGranted && !store.eventCalendars.isEmpty
                    ? .picker(action: { store.send(.overlayOpened(.eventCalendar)) })
                    : .disabledPicker
            )
            // URL + Location are `.inline` / `.inlineWithSuggestions`
            // TextFields. There is no `.disabledInline` behavior —
            // disabling them via `.disabledPicker` would render a
            // misleading "tap to pick" chevron row that does nothing.
            // When permission isn't granted the whole form is overlaid
            // by the permission card anyway, so omitting these rows
            // costs the user no real capability.
            var calendarFields: [DispatchView.Model.FieldRow] = []
            if isGranted {
                // Apple Calendar order: Title, Location, Starts, Ends,
                // Calendar, URL. Location sits right under the captured
                // line at the top of the form.
                let locationField = DispatchView.Model.Field(
                    kind: .location,
                    label: AppStrings.DispatchModal.location,
                    value: store.eventLocation,
                    placeholder: AppStrings.DispatchModal.locationPlaceholder,
                    behavior: .inlineWithSuggestions(
                        onChange: { value in store.send(.eventLocationChanged(value)) },
                        suggestions: Array(store.locationSuggestions),
                        onSuggestionTap: { s in store.send(.locationSuggestionTapped(s)) }
                    )
                )
                calendarFields.append(.full(locationField))
            }
            let recurrenceField = DispatchView.Model.Field(
                kind: .recurrence,
                label: AppStrings.DispatchModal.repeatLabel,
                value: Self.recurrenceLabel(store.eventRecurrence),
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.eventRecurrence)) })
                    : .disabledPicker
            )
            let alarmField = DispatchView.Model.Field(
                kind: .alarm,
                label: AppStrings.DispatchModal.alertLabel,
                value: AlarmPreset.from(minutesBefore: store.eventAlarmMinutesBefore).label,
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.eventAlarm)) })
                    : .disabledPicker
            )
            calendarFields.append(contentsOf: [
                .pair(date, time),
                .pair(endDate, endTime),
                .full(recurrenceField),
                .full(calendarField),
                .full(alarmField),
            ])
            if isGranted {
                let urlField = DispatchView.Model.Field(
                    kind: .url,
                    label: AppStrings.DispatchModal.url,
                    value: store.eventURL,
                    placeholder: AppStrings.DispatchModal.urlPlaceholder,
                    behavior: .inline(
                        keyboard: .url,
                        onChange: { value in store.send(.eventURLChanged(value)) }
                    )
                )
                calendarFields.append(.full(urlField))
            }
            fields = calendarFields

        case .reminders:
            let listTitle = store.reminderListID.flatMap { id in
                store.reminderLists[id: id]?.title
            } ?? store.reminderLists.first?.title ?? ""
            let list = DispatchView.Model.Field(
                kind: .list,
                label: AppStrings.DispatchModal.list,
                value: listTitle,
                placeholder: "",
                behavior: isGranted && !store.reminderLists.isEmpty
                    ? .picker(action: { store.send(.overlayOpened(.reminderList)) })
                    : .disabledPicker
            )
            let due = DispatchView.Model.Field(
                kind: .due,
                label: AppStrings.DispatchModal.due,
                value: Self.dueDisplay(
                    store.reminderDue,
                    hasTime: store.reminderHasTime,
                    cal: cal
                ),
                placeholder: "",
                behavior: isGranted
                    ? .picker(action: { store.send(.overlayOpened(.reminderDue)) })
                    : .disabledPicker
            )
            fields = [.pair(list, due)]

        case .mail:
            let to = DispatchView.Model.Field(
                kind: .to,
                label: AppStrings.DispatchModal.to,
                value: store.mailTo,
                placeholder: AppStrings.DispatchModal.mailToPlaceholder,
                behavior: .inline(
                    keyboard: .email,
                    onChange: { value in store.send(.mailToChanged(value)) }
                )
            )
            let subject = DispatchView.Model.Field(
                kind: .subject,
                label: AppStrings.DispatchModal.subject,
                value: store.effectiveMailSubject,
                placeholder: AppStrings.DispatchModal.mailSubjectPlaceholder,
                behavior: .inline(onChange: { value in store.send(.mailSubjectChanged(value)) })
            )
            fields = [.pair(to, subject)]
        }

        // Picker overlay payload (nil = no picker, just the main modal).
        let pickerOverlay: DispatchView.Model.PickerOverlay?
        switch store.openOverlay {
        case .calendarDate:
            pickerOverlay = .calendarPicker(.startDate, displayStart)
        case .calendarTime:
            pickerOverlay = .calendarPicker(.startTime, displayStart)
        case .calendarEndDate:
            pickerOverlay = .calendarPicker(.endDate, displayEnd)
        case .calendarEndTime:
            pickerOverlay = .calendarPicker(.endTime, displayEnd)
        case .eventCalendar:
            let choices = store.eventCalendars.map {
                DispatchView.Model.PickerChoice(id: $0.id, title: $0.title)
            }
            pickerOverlay = .eventCalendar(choices, selected: store.eventCalendarID)
        case .eventRecurrence:
            let choices = EventRecurrence.allCases.map {
                DispatchView.Model.PickerChoice(id: $0.rawValue, title: Self.recurrenceLabel($0))
            }
            pickerOverlay = .recurrence(choices, selected: store.eventRecurrence.rawValue)
        case .eventAlarm:
            let current = AlarmPreset.from(minutesBefore: store.eventAlarmMinutesBefore)
            var choices = AlarmPreset.allPresets.map {
                DispatchView.Model.PickerChoice(id: $0.id, title: $0.label)
            }
            // If state holds a non-preset value, append it as an extra
            // row at the end so the user can keep it (tap = no-op),
            // replace it (tap a preset), or clear it (tap None) without
            // us silently destroying the value.
            if case .custom = current {
                choices.append(.init(id: current.id, title: current.label))
            }
            pickerOverlay = .alarm(choices, selected: current.id)
        case .reminderDue:
            pickerOverlay = .reminderDue(store.reminderDue, hasTime: store.reminderHasTime)
        case .reminderList:
            let choices = store.reminderLists.map {
                DispatchView.Model.PickerChoice(id: $0.id, title: $0.title)
            }
            pickerOverlay = .reminderList(choices, selected: store.reminderListID)
        case .none:
            pickerOverlay = nil
        }

        // Permission card payload (nil when granted).
        let permissionCard: DispatchView.Model.PermissionCard?
        if isGranted {
            permissionCard = nil
        } else {
            let label = destinationChips.first { $0.id == destination.rawValue }?.label
                ?? destination.rawValue
            let isDenied = store.currentAuth == .denied || store.currentAuth == .restricted
            let verb = Self.permissionVerb(for: destination)
            let eyebrow = isDenied
                ? String.localizedStringWithFormat(
                    AppStrings.DispatchModal.accessDeniedTemplate, label)
                : String.localizedStringWithFormat(
                    AppStrings.DispatchModal.accessNeededTemplate, label)
            let body = isDenied
                ? String.localizedStringWithFormat(
                    NSLocalizedString(
                        "dispatch.modal.perm.body.denied",
                        value: "From Ink can't reach %1$@. Turn it back on in Settings to %2$@ from your notes.",
                        comment: "Body text on the permission card when access is denied. %1$@ destination, %2$@ verb."
                    ),
                    label, verb)
                : String.localizedStringWithFormat(
                    NSLocalizedString(
                        "dispatch.modal.perm.body.needed",
                        value: "From Ink uses %1$@ to %2$@ from your notes.",
                        comment: "Body text on the permission card when access is needed. %1$@ destination, %2$@ verb."
                    ),
                    label, verb)
            let hint = isDenied
                ? String.localizedStringWithFormat(
                    AppStrings.DispatchModal.permDeniedHintTemplate, label)
                : AppStrings.DispatchModal.permGrantedHint
            let cta = isDenied
                ? AppStrings.DispatchModal.permOpenSettings
                : String.localizedStringWithFormat(
                    AppStrings.DispatchModal.permAllowTemplate, label)
            permissionCard = .init(
                isDenied: isDenied,
                eyebrow: eyebrow,
                body: body,
                hint: hint,
                cta: cta
            )
        }

        let errorMessage: String? = {
            if case .failed(let msg) = store.saveState { return msg }
            return nil
        }()

        let destinationLabel = destinationChips.first { $0.id == destination.rawValue }?.label ?? ""
        let sendButtonLabel: String
        switch store.saveState {
        case .saving:
            sendButtonLabel = AppStrings.DispatchModal.sending
        case .idle, .failed:
            sendButtonLabel = AppStrings.DispatchModal.sendToButton(destination: destinationLabel)
        }

        self.init(
            eyebrowTitle: eyebrowTitle,
            eyebrowSubtitle: eyebrowSubtitle,
            isStack: store.isStack,
            canGoPrevious: store.currentIndex > 0,
            canGoNext: store.currentIndex < store.tasks.count - 1,
            onPreviousTask: { store.send(.previousTaskTapped) },
            onNextTask: { store.send(.nextTaskTapped) },
            onCancel: { store.send(.cancelTapped) },
            progress: progress,
            currentIndex: store.currentIndex,
            onTaskIndexSet: { idx in store.send(.taskIndexSet(idx)) },
            lineLabel: AppStrings.DispatchModal.line,
            editLabel: AppStrings.DispatchModal.edit,
            doneLabel: AppStrings.DispatchModal.done,
            isEditingLine: store.isEditingLine,
            onEditingChanged: { editing in store.send(.editingChanged(editing)) },
            isExtracting: store.isExtracting,
            extractingLabel: AppStrings.DispatchModal.extracting,
            extractingHeight: 280,
            // Brief height interpolation between the loading card
            // (280pt) and the resolved content's intrinsic height.
            // 120ms linear — within the project's standard motion
            // range, no special-case duration needed.
            contentSwapAnimation: ds.animation.slow,
            sendToLabel: AppStrings.DispatchModal.sendTo,
            destinationTabModel: destinationTabModel,
            isPermissionGranted: isGranted,
            fields: fields,
            noteLabel: AppStrings.DispatchModal.noteLabel,
            notePlaceholder: AppStrings.DispatchModal.notePlaceholder,
            permissionCard: permissionCard,
            onAllowAccess: { store.send(.allowAccessTapped) },
            cancelLabel: AppStrings.DispatchModal.cancel,
            skipLabel: AppStrings.DispatchModal.skip,
            sendButtonLabel: sendButtonLabel,
            canSend: store.canSend,
            onSkip: { store.send(.skipTapped) },
            onSend: { store.send(.sendTapped) },
            errorMessage: errorMessage,
            pickerOverlay: pickerOverlay,
            onPickerDismiss: { store.send(.overlayDismissed) },
            onCalendarPickerChanged: { kind, date in
                switch kind {
                case .startDate: store.send(.calendarDateChanged(date))
                case .startTime: store.send(.calendarTimeChanged(date))
                case .endDate:   store.send(.calendarEndDateChanged(date))
                case .endTime:   store.send(.calendarEndTimeChanged(date))
                }
            },
            onEventCalendarSelected: { id in
                store.send(.eventCalendarSelected(id))
                store.send(.overlayDismissed)
            },
            onRecurrenceSelected: { rawValue in
                store.send(.eventRecurrenceSelected(EventRecurrence(rawValue: rawValue) ?? .never))
                store.send(.overlayDismissed)
            },
            onAlarmSelected: { id in
                store.send(.eventAlarmSelected(AlarmPreset.from(id: id).minutesBefore))
                store.send(.overlayDismissed)
            },
            onReminderDueChanged: { date in store.send(.reminderDueChanged(date)) },
            onReminderHasTimeChanged: { hasTime in store.send(.reminderHasTimeChanged(hasTime)) },
            onReminderListSelected: { id in
                store.send(.reminderListSelected(id))
                store.send(.overlayDismissed)
            },
            hasTimeLabel: NSLocalizedString(
                "dispatch.modal.due.hasTime",
                value: "At a specific time",
                comment: "Toggle label for reminder due date carrying a time component"
            ),
            clearDueLabel: NSLocalizedString(
                "dispatch.modal.due.clear",
                value: "Clear",
                comment: "Button label that clears the reminder due date"
            ),
            locale: cal.userLocale(),
            calendar: cal.userCalendar(),
            timeZone: cal.userTimeZone(),
            nowFallback: cal.now(),
            scrimColor: ds.colors.ink.opacity(ds.layout.scrimOpacity),
            // Wider than the previous 520pt so the line / note get more
            // writing real estate. 640pt fits cleanly on iPad mini
            // (744pt portrait), iPad regular, and Mac.
            cardWidth: 640,
            pickerCardWidth: 380,
            scrollMaxHeight: 560,
            cardBackground: ds.colors.paper,
            paper: ds.colors.paper,
            surface: ds.colors.surface,
            ink: ds.colors.ink,
            ink2: ds.colors.ink2,
            ink3: ds.colors.ink3,
            rule: ds.colors.rule,
            borderColor: ds.colors.ink,
            borderWidth: ds.layout.borderWidth,
            errorColor: ds.colors.flagRed,
            horizontalPadding: 22,
            verticalPadding: 14,
            innerSpacing: 10,
            tightSpacing: 6,
            headerPadding: 12,
            eyebrowFont: .system(size: 10.5, weight: .medium, design: .monospaced),
            monoSmall: .system(size: 10.5, weight: .medium, design: .monospaced),
            monoTiny: .system(size: 9.5, weight: .medium, design: .monospaced),
            bodyFont: ds.typography.body,
            serifLineFont: .system(.title3, design: .serif),
            serifBodyFont: .system(.body, design: .serif),
            smallFont: .system(size: 12, weight: .regular),
            chevronFont: .system(size: 13, weight: .medium)
        )
    }

    // MARK: - Display helpers (locale-correct)

    /// Calendar date label — "Wed, May 28" in user locale.
    private static func dateOnlyDisplay(_ date: Date, cal: CalendarContext) -> String {
        date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(cal.userLocale())
        )
    }

    /// Calendar time label — "9:00 AM" / "09:00" by user locale.
    private static func timeOnlyDisplay(_ date: Date, cal: CalendarContext) -> String {
        date.formatted(
            .dateTime.hour().minute().locale(cal.userLocale())
        )
    }

    /// Reminder due-date label — "Wed, May 28" or "Wed, May 28 · 9:00 AM"
    /// or the localized "No due date" sentinel.
    private static func dueDisplay(_ date: Date?, hasTime: Bool, cal: CalendarContext) -> String {
        guard let date else {
            return NSLocalizedString(
                "dispatch.modal.due.none",
                value: "No due date",
                comment: "Displayed value when no reminder due date is set"
            )
        }
        if hasTime {
            return date.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                    .hour().minute()
                    .locale(cal.userLocale())
            )
        } else {
            return date.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                    .locale(cal.userLocale())
            )
        }
    }

    /// Maps an `EventRecurrence` to its localized picker label.
    /// Kept in the wiring because the enum lives in EventKitService
    /// (a dependency layer that shouldn't import AppStrings).
    private static func recurrenceLabel(_ r: EventRecurrence) -> String {
        switch r {
        case .never:    return AppStrings.DispatchModal.repeatNever
        case .daily:    return AppStrings.DispatchModal.repeatDaily
        case .weekly:   return AppStrings.DispatchModal.repeatWeekly
        case .biweekly: return AppStrings.DispatchModal.repeatBiweekly
        case .monthly:  return AppStrings.DispatchModal.repeatMonthly
        case .yearly:   return AppStrings.DispatchModal.repeatYearly
        }
    }

    private static func permissionVerb(for destination: DispatchFeature.State.Destination) -> String {
        switch destination {
        case .calendar:  return AppStrings.DispatchModal.permCalendarVerb
        case .reminders: return AppStrings.DispatchModal.permRemindersVerb
        case .mail:      return ""
        }
    }
}

// MARK: - Alarm presets (presentation only)

/// Bridge between the reducer's raw `Int?` (`eventAlarmMinutesBefore`)
/// and the picker's `String` IDs + localized labels. The reducer
/// itself never sees this type — it only stores the underlying
/// minutes value.
///
/// The seven preset cases (`none` … `oneDay`) match Apple Calendar's
/// quick-pick rotation; declaration order in `allPresets` is
/// load-bearing for the picker render order.
///
/// `.custom(Int)` preserves an alarm offset that doesn't match any
/// preset — currently only triggerable by round-tripping an existing
/// `EKEvent` whose alarm was set outside our preset list. The picker
/// surfaces it as an extra appended row labeled e.g. "7 min before"
/// so the user can keep, replace, or clear it without us silently
/// destroying the value (the bug documented in Stage 4b's review,
/// now fixed by this case existing).
///
/// `internal` (not `fileprivate`) so the test target can verify the
/// round-trip without going through TestStore.
enum AlarmPreset: Equatable {
    case none
    case atTime
    case fiveMin
    case fifteenMin
    case thirtyMin
    case oneHour
    case oneDay
    /// Non-preset offset loaded from an external source (an existing
    /// `EKEvent` with a custom alarm). Carries the raw minutes count.
    case custom(Int)

    /// The seven fixed picker rows, in render order. Declaration
    /// order matches Apple Calendar's list (None → at-time → ascending
    /// offsets). The custom row is NOT in this list — it gets
    /// appended dynamically by the wiring when state holds a value
    /// that doesn't match any preset.
    static let allPresets: [AlarmPreset] = [
        .none, .atTime, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .oneDay,
    ]

    /// Minutes-before-start offset. `nil` for `.none`; `0` for "at
    /// the moment the event starts."
    var minutesBefore: Int? {
        switch self {
        case .none:           return nil
        case .atTime:         return 0
        case .fiveMin:        return 5
        case .fifteenMin:     return 15
        case .thirtyMin:      return 30
        case .oneHour:        return 60
        case .oneDay:         return 1440
        case .custom(let m):  return m
        }
    }

    /// Stable string ID for the picker. Uses `"none"` for nil and the
    /// stringified minutes for everything else.
    ///
    /// **Uniqueness invariant (by convention, not by type):** every
    /// active value has a distinct `id` AS LONG AS callers route
    /// `.custom` construction through `from(minutesBefore:)` — the
    /// only invariant-preserving constructor, which routes preset
    /// minutes to their own cases. Writing `.custom(5)` directly
    /// would produce a value with `id == "5"`, colliding with
    /// `.fiveMin`'s `id == "5"` and tripping SwiftUI's duplicate-id
    /// warning in `ForEach(choices, id: \.id)`. The type system
    /// doesn't enforce this — don't bypass `from(minutesBefore:)`.
    var id: String {
        minutesBefore.map(String.init) ?? "none"
    }

    var label: String {
        switch self {
        case .none:           return AppStrings.DispatchModal.alertNone
        case .atTime:         return AppStrings.DispatchModal.alertAtTime
        case .fiveMin:        return AppStrings.DispatchModal.alertFiveMin
        case .fifteenMin:     return AppStrings.DispatchModal.alertFifteenMin
        case .thirtyMin:      return AppStrings.DispatchModal.alertThirtyMin
        case .oneHour:        return AppStrings.DispatchModal.alertOneHour
        case .oneDay:         return AppStrings.DispatchModal.alertOneDay
        case .custom(let m):
            return String.localizedStringWithFormat(
                AppStrings.DispatchModal.alertCustomMinutes, m
            )
        }
    }

    /// Map state's `Int?` back to a preset (or `.custom`) for the
    /// picker. A non-preset value is preserved via `.custom(m)` so
    /// the field display, picker row, and underlying state all agree
    /// — no masquerade-as-`.none` destroy-on-tap bug.
    static func from(minutesBefore minutes: Int?) -> AlarmPreset {
        switch minutes {
        case nil:             return .none
        case .some(0):        return .atTime
        case .some(5):        return .fiveMin
        case .some(15):       return .fifteenMin
        case .some(30):       return .thirtyMin
        case .some(60):       return .oneHour
        case .some(1440):     return .oneDay
        case .some(let m):    return .custom(m)
        }
    }

    /// Decode the picker ID emitted by `onAlarmSelected`. Tries the
    /// fixed presets first; falls back to parsing the ID as a positive
    /// minutes count so a custom row added dynamically by the wiring
    /// round-trips correctly.
    ///
    /// The `> 0` guard belts-and-braces against negative or zero
    /// minutes — neither is reachable from our own picker output
    /// (preset zero already routes to `.atTime` above; the picker
    /// never emits negative IDs), but a future path that pipes raw
    /// EKEvent TimeIntervals through here without normalizing sign
    /// would otherwise produce semantically incoherent `.custom(-5)`
    /// values that EKAlarm interprets as "after the event starts."
    static func from(id: String) -> AlarmPreset {
        if let preset = allPresets.first(where: { $0.id == id }) {
            return preset
        }
        if let minutes = Int(id), minutes > 0 {
            return .custom(minutes)
        }
        return .none
    }
}
