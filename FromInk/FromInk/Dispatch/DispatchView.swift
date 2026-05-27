import SwiftUI

/// Universal Dispatch modal — "one modal, three devices."
///
/// Layout (top → bottom):
///   1. Header: mono eyebrow ("✨ DISPATCH · 1 LINE" / "TASKS · 2 / 4"),
///      stack-mode prev/next arrows, close X.
///   2. Progress bar (stack mode only).
///   3. Line section: "LINE" label + Edit/Done, then the line in serif.
///   4. "Send to" — `InkTabStrip<Destination>` (the home-screen tab
///      pattern, reused). One unified strip with shared borders, active
///      cell inverts to ink fill.
///   5. Either:
///        a. Destination-aware fields (Calendar: Date + Time;
///           Reminders: List + Due; Mail: To + Subject) + optional note.
///        b. Permission card with Allow / Open Settings.
///   6. Footer: Skip (stack only) | Cancel | Send to [Destination].
///
/// On a field tap that needs a picker, a second overlay (smaller
/// branded card with `DatePicker(.graphical)` or `.wheel`) is presented
/// above this modal. The picker's own scrim dismisses on tap-out.
///
/// No TCA imports. The wiring view passes a flat `Model` plus two
/// bindings (line + note) for the text editors.
struct DispatchView: View {
    let model: Model
    @Binding var line: String
    @Binding var note: String

    var body: some View {
        ZStack {
            scrim
            modalCard
            if let overlay = model.pickerOverlay {
                pickerOverlay(overlay)
            }
        }
    }

    private var scrim: some View {
        model.scrimColor
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { model.onCancel() }
    }

    private var modalCard: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(model.rule).frame(height: model.borderWidth)

            if model.isStack {
                progressBar
                Rectangle().fill(model.rule).frame(height: model.borderWidth)
            }

            ScrollView {
                VStack(spacing: 0) {
                    lineSection
                    destinationTabs
                    if model.isPermissionGranted {
                        fieldsSection
                        noteSection
                    } else {
                        permissionCard
                    }
                    if let error = model.errorMessage {
                        Text(error)
                            .font(model.bodyFont)
                            .foregroundStyle(model.errorColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, model.horizontalPadding)
                            .padding(.vertical, model.verticalPadding)
                    }
                }
            }
            .frame(maxHeight: model.scrollMaxHeight)

            Rectangle().fill(model.rule).frame(height: model.borderWidth)
            footer
        }
        .frame(width: model.cardWidth)
        .background(model.cardBackground)
        .overlay(
            Rectangle().strokeBorder(model.borderColor, lineWidth: model.borderWidth)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: model.innerSpacing) {
            HStack(spacing: model.tightSpacing) {
                Image(systemName: "sparkles")
                    .font(model.eyebrowFont)
                    .foregroundStyle(model.ink)
                Text(model.eyebrowTitle)
                    .font(model.eyebrowFont)
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(model.ink)
                Text("·")
                    .font(model.eyebrowFont)
                    .foregroundStyle(model.ink3)
                Text(model.eyebrowSubtitle)
                    .font(model.eyebrowFont)
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(model.ink2)
            }
            Spacer(minLength: 0)
            if model.isStack {
                Button(action: model.onPreviousTask) {
                    Image(systemName: "chevron.backward")
                        .font(model.chevronFont)
                        .foregroundStyle(model.canGoPrevious ? model.ink : model.ink3)
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoPrevious)

                Button(action: model.onNextTask) {
                    Image(systemName: "chevron.forward")
                        .font(model.chevronFont)
                        .foregroundStyle(model.canGoNext ? model.ink : model.ink3)
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoNext)
            }
            Button(action: model.onCancel) {
                Image(systemName: "xmark")
                    .font(model.chevronFont)
                    .foregroundStyle(model.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.vertical, model.headerPadding)
    }

    // MARK: - Progress bar (stack only)

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.progress.enumerated()), id: \.offset) { (index, state) in
                Rectangle()
                    .fill(progressFill(for: state, isCurrent: index == model.currentIndex))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { model.onTaskIndexSet(index) }
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.vertical, model.tightSpacing)
    }

    private func progressFill(for state: Model.ProgressMark, isCurrent: Bool) -> Color {
        switch state {
        case .sent:    return model.ink
        case .skipped: return model.rule
        case .pending: return isCurrent ? model.ink : model.rule
        }
    }

    // MARK: - Line

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: model.tightSpacing) {
            HStack {
                monoLabel(model.lineLabel)
                Spacer(minLength: 0)
                Button(action: { model.onEditingChanged(!model.isEditingLine) }) {
                    HStack(spacing: model.tightSpacing) {
                        if !model.isEditingLine {
                            Image(systemName: "pencil")
                                .font(model.smallFont)
                                .foregroundStyle(model.ink2)
                        }
                        Text(model.isEditingLine ? model.doneLabel : model.editLabel)
                            .font(model.monoSmall)
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(model.isEditingLine ? model.ink : model.ink2)
                    }
                }
                .buttonStyle(.plain)
            }

            if model.isEditingLine {
                TextField("", text: $line, axis: .vertical)
                    .font(model.serifLineFont)
                    .foregroundStyle(model.ink)
                    .lineLimit(1...4)
                    .padding(model.innerSpacing)
                    .background(model.cardBackground)
                    .overlay(
                        Rectangle().strokeBorder(model.ink, lineWidth: model.borderWidth)
                    )
            } else {
                Button(action: { model.onEditingChanged(true) }) {
                    Text(line)
                        .font(model.serifLineFont)
                        .foregroundStyle(model.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.verticalPadding + 4)
    }

    // MARK: - Destination tabs (reuses InkTabStrip)

    private var destinationTabs: some View {
        VStack(alignment: .leading, spacing: model.innerSpacing) {
            monoLabel(model.sendToLabel)
            InkTabStrip<String>(model: model.destinationTabModel)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.verticalPadding + 6)
    }

    // MARK: - Fields

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(spacing: model.innerSpacing) {
            HStack(alignment: .top, spacing: model.innerSpacing) {
                fieldCell(model.fieldA)
                fieldCell(model.fieldB)
            }
            if let fieldC = model.fieldC {
                fieldCell(fieldC)
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.verticalPadding)
    }

    private func fieldCell(_ field: Model.Field) -> some View {
        VStack(alignment: .leading, spacing: model.tightSpacing) {
            monoLabel(field.label)
            if field.isInline {
                TextField(field.placeholder, text: Binding(
                    get: { field.value },
                    set: { field.onTextChange?($0) }
                ))
                .textFieldStyle(.plain)
                .font(model.bodyFont)
                .foregroundStyle(model.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(
                    Rectangle().strokeBorder(model.rule, lineWidth: model.borderWidth)
                )
            } else {
                Button(action: { field.onTap?() }) {
                    HStack {
                        Text(field.value.isEmpty ? "—" : field.value)
                            .font(model.bodyFont)
                            .foregroundStyle(model.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(model.chevronFont)
                            .foregroundStyle(model.ink2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(
                        Rectangle().strokeBorder(model.rule, lineWidth: model.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .disabled(field.onTap == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: model.tightSpacing) {
            monoLabel(model.noteLabel)
            TextField(model.notePlaceholder, text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(model.serifBodyFont)
                .foregroundStyle(model.ink)
                .lineLimit(2...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(
                    Rectangle().strokeBorder(model.rule, lineWidth: model.borderWidth)
                )
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.vertical, model.verticalPadding)
    }

    // MARK: - Permission card

    @ViewBuilder
    private var permissionCard: some View {
        if let card = model.permissionCard {
            VStack(alignment: .leading, spacing: model.tightSpacing) {
                HStack(spacing: model.tightSpacing) {
                    Image(systemName: card.isDenied ? "lock.fill" : "lock")
                        .font(model.smallFont)
                        .foregroundStyle(card.isDenied ? model.ink : model.ink2)
                    Text(card.eyebrow)
                        .font(model.monoSmall)
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(card.isDenied ? model.ink : model.ink2)
                }
                Text(card.body)
                    .font(model.serifBodyFont)
                    .foregroundStyle(model.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)

                HStack {
                    Text(card.hint)
                        .font(model.monoTiny)
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(model.ink3)
                    Spacer(minLength: 0)
                    Button(action: model.onAllowAccess) {
                        HStack(spacing: model.tightSpacing) {
                            Text(card.cta)
                                .font(model.monoSmall)
                                .tracking(1.4)
                                .textCase(.uppercase)
                                .foregroundStyle(model.paper)
                            if card.isDenied {
                                Image(systemName: "chevron.forward")
                                    .font(model.chevronFont)
                                    .foregroundStyle(model.paper)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(model.ink)
                        .overlay(
                            Rectangle().strokeBorder(model.ink, lineWidth: model.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(model.horizontalPadding)
            .overlay(
                Rectangle().strokeBorder(model.ink, lineWidth: model.borderWidth)
            )
            .padding(.horizontal, model.horizontalPadding)
            .padding(.top, model.verticalPadding)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: model.tightSpacing) {
            if model.isStack {
                Button(action: model.onSkip) {
                    Text(model.skipLabel)
                        .font(model.bodyFont)
                        .foregroundStyle(model.ink2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(
                            Rectangle().strokeBorder(model.rule, lineWidth: model.borderWidth)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button(action: model.onCancel) {
                Text(model.cancelLabel)
                    .font(model.bodyFont)
                    .foregroundStyle(model.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(
                        Rectangle().strokeBorder(model.ink, lineWidth: model.borderWidth)
                    )
            }
            .buttonStyle(.plain)
            Button(action: model.onSend) {
                Text(model.sendButtonLabel)
                    .font(model.monoSmall)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(model.canSend ? model.paper : model.ink3)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(model.canSend ? model.ink : model.surface)
                    .overlay(
                        Rectangle().strokeBorder(
                            model.canSend ? model.ink : model.rule,
                            lineWidth: model.borderWidth
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.vertical, model.verticalPadding)
    }

    // MARK: - Picker overlay (modal-over-modal)

    /// A second overlay above the Dispatch card. Renders a smaller
    /// branded card with the appropriate picker for the field that was
    /// tapped (graphical DatePicker for date, wheel for time, list of
    /// choices for List). Tapping outside or hitting Done dismisses.
    private func pickerOverlay(_ overlay: Model.PickerOverlay) -> some View {
        ZStack {
            model.scrimColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.onPickerDismiss() }

            VStack(spacing: 0) {
                HStack {
                    Text(overlay.title)
                        .font(model.monoSmall)
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(model.ink2)
                    Spacer(minLength: 0)
                    Button(action: model.onPickerDismiss) {
                        Text(model.doneLabel)
                            .font(model.monoSmall)
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(model.ink)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, model.horizontalPadding)
                .padding(.vertical, model.headerPadding)
                Rectangle().fill(model.rule).frame(height: model.borderWidth)

                pickerContent(overlay)
                    .padding(.horizontal, model.horizontalPadding)
                    .padding(.vertical, model.verticalPadding)
            }
            .frame(width: model.pickerCardWidth)
            .background(model.cardBackground)
            .overlay(
                Rectangle().strokeBorder(model.borderColor, lineWidth: model.borderWidth)
            )
        }
    }

    @ViewBuilder
    private func pickerContent(_ overlay: Model.PickerOverlay) -> some View {
        switch overlay {
        case .calendarDate(let date):
            DatePicker(
                selection: Binding(
                    get: { date },
                    set: { model.onCalendarDateChanged?($0) }
                ),
                displayedComponents: [.date]
            ) { EmptyView() }
            .labelsHidden()
            .datePickerStyle(.graphical)
            .tint(model.ink)
            .environment(\.locale, model.locale)
            .environment(\.calendar, model.calendar)
            .environment(\.timeZone, model.timeZone)

        case .calendarTime(let date):
            DatePicker(
                selection: Binding(
                    get: { date },
                    set: { model.onCalendarTimeChanged?($0) }
                ),
                displayedComponents: [.hourAndMinute]
            ) { EmptyView() }
            .labelsHidden()
            .datePickerStyle(.wheel)
            .tint(model.ink)
            .environment(\.locale, model.locale)
            .environment(\.calendar, model.calendar)
            .environment(\.timeZone, model.timeZone)
            .frame(maxWidth: .infinity)

        case .reminderDue(let date, let hasTime):
            VStack(alignment: .leading, spacing: model.innerSpacing) {
                DatePicker(
                    selection: Binding(
                        get: { date ?? model.nowFallback },
                        set: { model.onReminderDueChanged?($0) }
                    ),
                    displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                ) { EmptyView() }
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(model.ink)
                .environment(\.locale, model.locale)
                .environment(\.calendar, model.calendar)
                .environment(\.timeZone, model.timeZone)

                HStack {
                    Toggle(isOn: Binding(
                        get: { hasTime },
                        set: { model.onReminderHasTimeChanged?($0) }
                    )) {
                        Text(model.hasTimeLabel)
                            .font(model.bodyFont)
                            .foregroundStyle(model.ink2)
                    }
                    .tint(model.ink)
                    if date != nil {
                        Button(action: { model.onReminderDueChanged?(nil) }) {
                            Text(model.clearDueLabel)
                                .font(model.monoSmall)
                                .tracking(1.4)
                                .textCase(.uppercase)
                                .foregroundStyle(model.ink2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .reminderList(let lists, let selected):
            singleSelectList(lists, selected: selected, onTap: { id in
                model.onReminderListSelected?(id)
            })

        case .eventCalendar(let calendars, let selected):
            singleSelectList(calendars, selected: selected, onTap: { id in
                model.onEventCalendarSelected?(id)
            })
        }
    }

    @ViewBuilder
    private func singleSelectList(
        _ choices: [Model.PickerChoice],
        selected: String?,
        onTap: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(choices, id: \.id) { choice in
                Button(action: { onTap(choice.id) }) {
                    HStack {
                        Text(choice.title)
                            .font(model.bodyFont)
                            .foregroundStyle(model.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if choice.id == selected {
                            Image(systemName: "checkmark")
                                .font(model.smallFont)
                                .foregroundStyle(model.ink)
                        }
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if choice.id != choices.last?.id {
                    Rectangle().fill(model.rule).frame(height: model.borderWidth)
                }
            }
        }
    }

    // MARK: - Local helpers

    private func monoLabel(_ text: String) -> some View {
        Text(text)
            .font(model.monoSmall)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(model.ink2)
    }
}

// MARK: - Model

extension DispatchView {
    struct Model {
        // Header
        let eyebrowTitle: String
        let eyebrowSubtitle: String
        let isStack: Bool
        let canGoPrevious: Bool
        let canGoNext: Bool
        let onPreviousTask: () -> Void
        let onNextTask: () -> Void
        let onCancel: () -> Void

        // Progress (stack only)
        let progress: [ProgressMark]
        let currentIndex: Int
        let onTaskIndexSet: (Int) -> Void

        // Line
        let lineLabel: String
        let editLabel: String
        let doneLabel: String
        let isEditingLine: Bool
        let onEditingChanged: (Bool) -> Void

        // Destinations — flat InkTabStrip model, fully resolved by adapter.
        let sendToLabel: String
        let destinationTabModel: InkTabStrip<String>.Model

        // Fields (destination-aware). `fieldA` + `fieldB` render
        // side-by-side as a 2-col row. `fieldC` is optional and renders
        // full-width on its own row below — used by Calendar to host
        // the "Calendar" selector beneath the Date+Time row.
        let isPermissionGranted: Bool
        let fieldA: Field
        let fieldB: Field
        let fieldC: Field?

        // Note
        let noteLabel: String
        let notePlaceholder: String

        // Permission card (nil when granted)
        let permissionCard: PermissionCard?
        let onAllowAccess: () -> Void

        // Footer
        let cancelLabel: String
        let skipLabel: String
        let sendButtonLabel: String
        let canSend: Bool
        let onSkip: () -> Void
        let onSend: () -> Void

        // Error banner
        let errorMessage: String?

        // Picker overlay
        let pickerOverlay: PickerOverlay?
        let onPickerDismiss: () -> Void
        let onCalendarDateChanged: ((Date) -> Void)?
        let onCalendarTimeChanged: ((Date) -> Void)?
        let onEventCalendarSelected: ((String) -> Void)?
        let onReminderDueChanged: ((Date?) -> Void)?
        let onReminderHasTimeChanged: ((Bool) -> Void)?
        let onReminderListSelected: ((String) -> Void)?
        let hasTimeLabel: String
        let clearDueLabel: String

        // Locale plumbing for DatePickers (sourced from CalendarContext).
        let locale: Locale
        let calendar: Calendar
        let timeZone: TimeZone
        let nowFallback: Date

        // Visual tokens
        let scrimColor: Color
        let cardWidth: CGFloat
        let pickerCardWidth: CGFloat
        let scrollMaxHeight: CGFloat
        let cardBackground: Color
        let paper: Color
        let surface: Color
        let ink: Color
        let ink2: Color
        let ink3: Color
        let rule: Color
        let borderColor: Color
        let borderWidth: CGFloat
        let errorColor: Color
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let innerSpacing: CGFloat
        let tightSpacing: CGFloat
        let headerPadding: CGFloat
        let eyebrowFont: Font
        let monoSmall: Font
        let monoTiny: Font
        let bodyFont: Font
        let serifLineFont: Font
        let serifBodyFont: Font
        let smallFont: Font
        let chevronFont: Font

        struct Field {
            let label: String
            let value: String
            let placeholder: String
            /// True for inline text fields (Mail "To" / "Subject");
            /// false for tap-to-open-picker fields (Date / Time / List / Due).
            let isInline: Bool
            let onTap: (() -> Void)?
            let onTextChange: ((String) -> Void)?
        }

        enum ProgressMark: Equatable {
            case sent
            case skipped
            case pending
        }

        enum PickerOverlay: Equatable {
            case calendarDate(Date)
            case calendarTime(Date)
            case eventCalendar([PickerChoice], selected: String?)
            case reminderDue(Date?, hasTime: Bool)
            case reminderList([PickerChoice], selected: String?)

            var title: String {
                switch self {
                case .calendarDate:  return AppStrings.DispatchModal.date
                case .calendarTime:  return AppStrings.DispatchModal.time
                case .eventCalendar: return AppStrings.DispatchModal.calendar
                case .reminderDue:   return AppStrings.DispatchModal.due
                case .reminderList:  return AppStrings.DispatchModal.list
                }
            }
        }

        /// Single-select picker row used by both the event-calendar
        /// picker and the reminder-list picker (and any future
        /// single-select destination field).
        struct PickerChoice: Equatable, Identifiable {
            let id: String
            let title: String
        }

        struct PermissionCard: Equatable {
            let isDenied: Bool
            let eyebrow: String
            let body: String
            let hint: String
            let cta: String
        }
    }
}
