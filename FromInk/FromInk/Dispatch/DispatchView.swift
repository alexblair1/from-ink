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

    /// HIG compliance — when the user has enabled "Reduce Motion," the
    /// reveal transition collapses to a plain opacity fade.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Loading-to-content swap — content snaps in, only the card
        // height interpolates. No fade on the branches themselves; the
        // user found the crossfade janky. The visible animation is
        // SwiftUI growing the parent from the loading height (280pt) to
        // the resolved content's intrinsic height; the inner views are
        // simply present once they exist. Reduce Motion collapses to
        // an instant resize.
        ZStack {
            if model.isExtracting {
                extractingCard
            } else {
                resolvedCard
            }
        }
        .animation(reduceMotion ? nil : model.contentSwapAnimation, value: model.isExtracting)
        .frame(width: model.cardWidth)
        .background(model.cardBackground)
        .overlay(
            Rectangle().strokeBorder(model.borderColor, lineWidth: model.borderWidth)
        )
    }

    /// Extraction-in-flight: card contents are nothing but a centered
    /// reading indicator. Header chrome, destination grid, fields, and
    /// footer all stay hidden until the real content lands via
    /// `.extractionCompleted`. Scrim tap still dismisses (handled in
    /// the outer ZStack).
    private var extractingCard: some View {
        ReadingIndicator(model: .init(label: model.extractingLabel))
            .frame(height: model.extractingHeight)
    }

    private var resolvedCard: some View {
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
                    // Destination ("Send to:") strip only makes sense
                    // for new captures. An existing event already has
                    // a destination — calendar — and the user can't
                    // re-target it from this modal.
                    if !model.isEditing {
                        destinationTabs
                    }
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: model.innerSpacing) {
            HStack(spacing: model.tightSpacing) {
                // Sparkles signal "AI-extracted" — only meaningful for
                // new captures, hidden when editing existing events.
                if !model.isEditing {
                    Image(systemName: "sparkles")
                        .font(model.eyebrowFont)
                        .foregroundStyle(model.ink)
                }
                Text(model.eyebrowTitle)
                    .font(model.eyebrowFont)
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(model.ink)
                if let subtitle = model.eyebrowSubtitle {
                    Text("·")
                        .font(model.eyebrowFont)
                        .foregroundStyle(model.ink3)
                    Text(subtitle)
                        .font(model.eyebrowFont)
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(model.ink2)
                }
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
            ForEach(model.fields) { row in
                switch row {
                case .pair(let a, let b):
                    HStack(alignment: .top, spacing: model.innerSpacing) {
                        fieldCell(a)
                        fieldCell(b)
                    }
                case .full(let f):
                    fieldCell(f)
                }
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.verticalPadding)
    }

    private func fieldCell(_ field: Model.Field) -> some View {
        VStack(alignment: .leading, spacing: model.tightSpacing) {
            monoLabel(field.label)
            switch field.behavior {
            case .picker(let action):
                pickerCell(value: field.value, isEnabled: true, action: action)
            case .disabledPicker:
                pickerCell(value: field.value, isEnabled: false, action: {})
            case .inline(let keyboard, let onChange):
                inlineTextField(field: field, keyboard: keyboard, onChange: onChange)
            case .inlineWithSuggestions(let onChange, let suggestions, let onTap):
                VStack(spacing: model.tightSpacing) {
                    // Location field — `.placeName` keyboard profile
                    // matches Apple Calendar: autocorrect off so place
                    // names don't get mangled, `.words` autocaps so
                    // "Apple Park" / "Conference Room A" capitalize
                    // naturally. MapKit autocomplete drives the real
                    // entry below.
                    inlineTextField(field: field, keyboard: .placeName, onChange: onChange)
                    if !suggestions.isEmpty {
                        suggestionsList(suggestions: suggestions, onTap: onTap)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineTextField(
        field: Model.Field,
        keyboard: Model.Field.InlineKeyboard,
        onChange: @escaping (String) -> Void
    ) -> some View {
        TextField(field.placeholder, text: Binding(
            get: { field.value },
            set: { onChange($0) }
        ))
        .textFieldStyle(.plain)
        .font(model.bodyFont)
        .foregroundStyle(model.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            Rectangle().strokeBorder(model.rule, lineWidth: model.borderWidth)
        )
        .modifier(InlineKeyboardModifier(keyboard: keyboard))
    }

    @ViewBuilder
    private func suggestionsList(
        suggestions: [LocationSuggestion],
        onTap: @escaping (LocationSuggestion) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button(action: { onTap(suggestion) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(model.bodyFont)
                            .foregroundStyle(model.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(model.smallFont)
                                .foregroundStyle(model.ink2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if suggestion.id != suggestions.last?.id {
                    Rectangle().fill(model.rule).frame(height: model.borderWidth)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(model.rule, lineWidth: model.borderWidth))
    }

    /// Shared picker-cell chrome (value text + chevron + bordered row).
    /// Single render path for both `.picker` and `.disabledPicker` —
    /// the only difference is the `.disabled` modifier and which
    /// action runs on tap.
    private func pickerCell(value: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(value.isEmpty ? AppStrings.Common.emptyValuePlaceholder : value)
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
        .disabled(!isEnabled)
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
        case .calendarPicker(let kind, let date):
            calendarPickerView(kind: kind, date: date)

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

        case .recurrence(let choices, let selected):
            singleSelectList(choices, selected: selected, onTap: { id in
                model.onRecurrenceSelected?(id)
            })

        case .alarm(let choices, let selected):
            singleSelectList(choices, selected: selected, onTap: { id in
                model.onAlarmSelected?(id)
            })
        }
    }

    /// All four calendar pickers (start/end × date/time) share an
    /// identical modifier chain — only the displayed components and
    /// the `.datePickerStyle` differ. Branching on `kind.isTime` here
    /// keeps the switch in `pickerContent` to one calendar arm.
    @ViewBuilder
    private func calendarPickerView(
        kind: Model.PickerOverlay.CalendarPickerKind,
        date: Date
    ) -> some View {
        // Time pickers snap to 5-minute intervals on every set —
        // matches Calendar.app / Reminders.app behavior. SwiftUI's
        // DatePicker doesn't expose a native `minuteInterval` for
        // the wheel style, so we round the bound value in the setter.
        // Read-side passes through untouched so a snap doesn't fight
        // the user mid-spin; the round happens when the parent commits.
        let binding = Binding(
            get: { date },
            set: { newValue in
                let snapped = kind.isTime
                    ? Self.roundDateToFiveMinutes(newValue, calendar: model.calendar)
                    : newValue
                model.onCalendarPickerChanged?(kind, snapped)
            }
        )
        if kind.isTime {
            DatePicker(selection: binding, displayedComponents: [.hourAndMinute]) {
                EmptyView()
            }
            .labelsHidden()
            .datePickerStyle(.wheel)
            .tint(model.ink)
            .environment(\.locale, model.locale)
            .environment(\.calendar, model.calendar)
            .environment(\.timeZone, model.timeZone)
            .frame(maxWidth: .infinity)
        } else {
            DatePicker(selection: binding, displayedComponents: [.date]) {
                EmptyView()
            }
            .labelsHidden()
            .datePickerStyle(.graphical)
            .tint(model.ink)
            .environment(\.locale, model.locale)
            .environment(\.calendar, model.calendar)
            .environment(\.timeZone, model.timeZone)
        }
    }

    /// Rounds a date's minute component to the nearest 5-minute
    /// boundary using the supplied calendar so the snap respects the
    /// user's locale (calendar identifier + timezone) rather than the
    /// process default.
    /// Bias: nearest, with .5 rounding up (10:32 → 10:30, 10:33 → 10:35).
    ///
    /// `Calendar.dateInterval(of: .minute, for:)` zeros seconds and
    /// nanoseconds Calendar-natively; `Calendar.date(byAdding: .minute,
    /// value:, to:)` handles all hour / day / month / year rollovers
    /// including DST transitions. Both per the dates EDD — don't
    /// inline raw `addingTimeInterval` arithmetic on minutes.
    static func roundDateToFiveMinutes(_ date: Date, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let snapped = Int((Double(minute) / 5.0).rounded()) * 5
        let startOfMinute = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return calendar.date(byAdding: .minute, value: snapped - minute, to: startOfMinute) ?? date
    }

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
        /// `nil` means the eyebrow renders just the title (no "·" or
        /// trailing subtitle). The wiring passes `nil` in edit mode;
        /// keying the view's render decision off nil-ness rather than
        /// off the semantic `isEditing` flag means any other "no
        /// subtitle" case (a future minimal-header modal, etc.) drops
        /// in without needing a different discriminator.
        let eyebrowSubtitle: String?
        /// True when the modal is editing an existing calendar event.
        /// Hides the sparkle "AI-extracted" badge and the destination
        /// tab strip — the user isn't choosing a destination, just
        /// editing one that's already targeted. Subtitle absence is
        /// keyed off `eyebrowSubtitle == nil` independently.
        let isEditing: Bool
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
        /// True while upstream extraction (OCR) is in flight. View
        /// replaces the entire card contents (header, line, destinations,
        /// fields, footer) with a centered loading indicator until the
        /// reducer dispatches `.extractionCompleted`.
        let isExtracting: Bool
        let extractingLabel: String
        /// Height of the loading-only card. Roughly matches the
        /// expected height of the resolved card so the modal doesn't
        /// jump when content swaps in.
        let extractingHeight: CGFloat

        /// Animation token for the in-card load → content crossfade.
        /// Sourced from `AnimationTokens.standard` (100ms linear) per
        /// the project's style guide. Don't hardcode `.linear(duration:)`
        /// at the call site — use this token.
        let contentSwapAnimation: Animation

        // Destinations — flat InkTabStrip model, fully resolved by adapter.
        let sendToLabel: String
        let destinationTabModel: InkTabStrip<String>.Model

        // Fields (destination-aware). Rows lay out top-to-bottom; each
        // row is either a `.pair(Field, Field)` (two cells side-by-side)
        // or a `.full(Field)` (single cell spanning the row). Reminders
        // and Mail use a single pair today; Calendar uses pair + full,
        // and will grow to many rows in Stage 3.
        let isPermissionGranted: Bool
        let fields: [FieldRow]

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
        let onCalendarPickerChanged: ((PickerOverlay.CalendarPickerKind, Date) -> Void)?
        let onEventCalendarSelected: ((String) -> Void)?
        let onRecurrenceSelected: ((String) -> Void)?
        let onAlarmSelected: ((String) -> Void)?
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
            /// Semantic role of the field. Drives stable SwiftUI
            /// identity (so a row swap doesn't trigger focus loss or
            /// animation cross-fade) and lets the adapter declare what
            /// each row IS without parsing labels.
            ///
            /// **Convention:** `kind` and `behavior` are independently
            /// typed but conventionally paired by the adapter:
            ///   - Tap-to-open-picker kinds (date, time, endDate, endTime,
            ///     eventCalendar, location, recurrence, alarm, list, due)
            ///     pair with `.picker` or `.disabledPicker`.
            ///   - Inline-text-input kinds (url, to, subject) pair with
            ///     `.inline`.
            /// The compiler doesn't enforce this — only the adapter
            /// (single construction site) does. If we ever introduce a
            /// second construction site, consider a generic phantom
            /// type to lift the convention into the type system.
            let kind: Kind
            let label: String
            let value: String
            let placeholder: String
            let behavior: Behavior

            /// Every field that could appear in any destination form,
            /// enumerated. Adding a destination field requires a case
            /// here — the compiler then surfaces every site that needs
            /// to update.
            enum Kind: String {
                // Calendar
                case date, time, endDate, endTime
                case eventCalendar
                case location, url
                case recurrence, alarm
                // Reminders
                case list, due
                // Mail
                case to, subject
            }

            /// Tap-to-open-picker vs. inline-text-field, modeled as a
            /// sum type so the two callback styles are mutually
            /// exclusive at the type level. The "no choices to offer"
            /// case is its own variant rather than an optional closure
            /// inside `.picker` — three explicit cases, zero optionals,
            /// switch exhaustiveness covers every render path.
            enum Behavior {
                /// Tappable picker row with a real action.
                case picker(action: () -> Void)
                /// Picker row rendered in a disabled state. Used when the
                /// picker has no choices to offer (e.g., a Reminders list
                /// picker when the user has no writable lists).
                case disabledPicker
                /// Inline `TextField`. The closure receives every keystroke.
                /// `keyboard` picks the right iOS soft-keyboard layout +
                /// content type + autocorrect/autocaps profile for the
                /// field — `.url` for URL input, `.email` for email
                /// addresses, `.standard` for everything else.
                case inline(keyboard: InlineKeyboard = .standard, onChange: (String) -> Void)
                /// Inline `TextField` plus a live autocomplete list
                /// rendered directly below. Used by the location field —
                /// each keystroke flows out via `onChange`, and tapping
                /// a row flows out via `onSuggestionTap`. The view does
                /// not own the search lifecycle; the reducer drives the
                /// autocomplete stream and feeds `suggestions` back in.
                case inlineWithSuggestions(
                    onChange: (String) -> Void,
                    suggestions: [LocationSuggestion],
                    onSuggestionTap: (LocationSuggestion) -> Void
                )
            }

            /// iOS soft-keyboard profile for an `.inline` TextField. The
            /// view applies the matching `.keyboardType`, `.textContentType`,
            /// `.autocorrectionDisabled`, and `.textInputAutocapitalization`
            /// modifiers; macOS / Catalyst ignore these and fall back to a
            /// plain text field.
            ///
            /// `.placeName` matches Apple Calendar's location field —
            /// autocorrect off (so "5th Ave" doesn't become "5th Avenue",
            /// "WeWork" doesn't become "We work"), `.words` autocaps so
            /// place names like "Apple Park" or "Conference Room A"
            /// still capitalize naturally as the user types.
            enum InlineKeyboard {
                case standard
                case email
                case url
                case placeName
            }
        }

        /// One row in the destination-aware fields section. Pairs render
        /// two `Field` cells side-by-side (when the two fields naturally
        /// read together — Date + Time, To + Subject); `.full` renders
        /// a single cell spanning the row width (for solo fields like
        /// Calendar selector, Location, URL).
        enum FieldRow: Identifiable {
            case pair(Field, Field)
            case full(Field)

            /// Stable per-role id so SwiftUI doesn't conflate two
            /// semantically distinct rows that happen to land at the
            /// same index (which would cause focus loss and animation
            /// discontinuities when conditional rows enter or leave).
            ///
            /// **Uniqueness invariant:** the adapter MUST emit at most
            /// one row per `Field.Kind` per render. Two `.full` rows
            /// sharing a Kind, or a `.pair` whose two kinds match
            /// another row's pair (in either order), would collide and
            /// trigger SwiftUI's "ForEach with duplicate id" warning at
            /// runtime. Naturally maintained because each destination
            /// form lists each field exactly once — but worth knowing
            /// before adding repeated rows (e.g., multiple alarms).
            var id: String {
                switch self {
                case .pair(let a, let b):
                    "pair-\(a.kind.rawValue)-\(b.kind.rawValue)"
                case .full(let f):
                    "full-\(f.kind.rawValue)"
                }
            }
        }

        enum ProgressMark: Equatable {
            case sent
            case skipped
            case pending
        }

        enum PickerOverlay: Equatable {
            /// All four calendar pickers (start/end × date/time) share
            /// identical structure — a `Date` payload and a date- or
            /// time-style DatePicker. Collapsed under one case with a
            /// `CalendarPickerKind` discriminator so the picker view
            /// has one switch arm per render style (date / time)
            /// instead of four.
            case calendarPicker(CalendarPickerKind, Date)
            case eventCalendar([PickerChoice], selected: String?)
            case recurrence([PickerChoice], selected: String)
            case alarm([PickerChoice], selected: String)
            case reminderDue(Date?, hasTime: Bool)
            case reminderList([PickerChoice], selected: String?)

            enum CalendarPickerKind: Equatable {
                case startDate, startTime, endDate, endTime

                /// Time pickers render `.wheel`, date pickers render `.graphical`.
                var isTime: Bool {
                    switch self {
                    case .startTime, .endTime: return true
                    case .startDate, .endDate: return false
                    }
                }

                var title: String {
                    switch self {
                    case .startDate: return AppStrings.DispatchModal.date
                    case .startTime: return AppStrings.DispatchModal.time
                    case .endDate:   return AppStrings.DispatchModal.endDate
                    case .endTime:   return AppStrings.DispatchModal.endTime
                    }
                }
            }

            var title: String {
                switch self {
                case .calendarPicker(let kind, _): return kind.title
                case .eventCalendar:               return AppStrings.DispatchModal.calendar
                case .recurrence:                  return AppStrings.DispatchModal.repeatLabel
                case .alarm:                       return AppStrings.DispatchModal.alertLabel
                case .reminderDue:                 return AppStrings.DispatchModal.due
                case .reminderList:                return AppStrings.DispatchModal.list
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

// MARK: - Inline keyboard modifier

/// Applies the right iOS soft-keyboard layout + content-type +
/// autocorrect / autocaps profile for an `.inline` TextField.
///
/// `.autocorrectionDisabled()` is cross-platform and lives outside
/// the `#if`. The iOS-only soft-keyboard, content-type, and
/// autocapitalization modifiers live inside it — macOS / Catalyst
/// hit the `#else` and fall through with just autocorrect off.
private struct InlineKeyboardModifier: ViewModifier {
    let keyboard: DispatchView.Model.Field.InlineKeyboard

    @ViewBuilder
    func body(content: Content) -> some View {
        switch keyboard {
        case .standard:
            content
        case .email:
            content
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
        case .url:
            content
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                #endif
        case .placeName:
            content
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.words)
                #endif
        }
    }
}
