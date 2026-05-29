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
            calendarFields.append(contentsOf: [
                .pair(date, time),
                .pair(endDate, endTime),
                .full(calendarField),
            ])
            if isGranted {
                let urlField = DispatchView.Model.Field(
                    kind: .url,
                    label: AppStrings.DispatchModal.url,
                    value: store.eventURL,
                    placeholder: AppStrings.DispatchModal.urlPlaceholder,
                    behavior: .inline(onChange: { value in store.send(.eventURLChanged(value)) })
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
                behavior: .inline(onChange: { value in store.send(.mailToChanged(value)) })
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

    private static func permissionVerb(for destination: DispatchFeature.State.Destination) -> String {
        switch destination {
        case .calendar:  return AppStrings.DispatchModal.permCalendarVerb
        case .reminders: return AppStrings.DispatchModal.permRemindersVerb
        case .mail:      return ""
        }
    }
}
