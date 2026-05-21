import SwiftUI

/// The daily brief section: meta row, date masthead, lede, time warp wheel,
/// editor's note, and the tab-based content (Calendar / Reminders /
/// Birthdays).
///
/// Replaces the previous counts-bar + highlights-section pattern with the
/// `BriefTabSection` composite — collapsed = tab strip alone; expanded =
/// tab strip + day header + tab-specific body.
///
/// Feature view — no TCA imports.
///
/// **Layout discipline:**
/// - The meta row (above the masthead) is ALWAYS rendered — opacity 0 in
///   wheel mode. Reason: hiding it would let the masthead slide upward,
///   which reads as the date label jumping. The row's reserved height is
///   small enough to be invisible when faded.
/// - The editor's note (below the wheel) is conditionally rendered. It's
///   tall (multi-paragraph), so keeping it in the tree at opacity 0 would
///   leave a large empty gap above the tab strip in wheel mode. Removing
///   it lets the tabs claim its space naturally.
///
struct HomeDailyBrief: View {
    let model: Model

    /// Honors the system "Reduce Motion" accessibility setting. When true,
    /// the wheel drawer falls back to a simple opacity fade rather than the
    /// height-clip drawer animation — required by Apple HIG.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BriefMetaRow(model: model.metaRow)
                .padding(.top, model.sectionSpacing)
                .opacity(model.metaRowOpacity)
                .allowsHitTesting(model.metaRowIsInteractive)
                .accessibilityHidden(!model.metaRowIsInteractive)
                .overlay(scrimOverlay(action: model.metaRowScrimAction))

            // Focal — masthead is the wheel's tap target; ← TODAY button
            // appears to the right only when warped.
            HStack(alignment: .firstTextBaseline, spacing: model.innerSpacing) {
                Button(action: model.onDateTapped) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        MastheadDateBlock(model: model.dateBlock)
                        if let pillModel = model.mastheadPill {
                            MastheadPill(model: pillModel)
                                .padding(.bottom, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.mastheadAccessibilityLabel)
                .accessibilityHint(model.mastheadAccessibilityHint)
                .accessibilityAddTraits(.isButton)

                Spacer(minLength: 0)

                if let backAction = model.backToTodayAction {
                    BackToTodayButton(
                        label: model.backToTodayLabel,
                        action: backAction
                    )
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.top, model.innerSpacing)

            // Focal — the time warp wheel + optional Done button. See
            // `DrawerTransition.swift` for why this transition is custom.
            if let wheelModel = model.timeWarpWheel {
                let naturalHeight = wheelModel.height + model.doneRowHeight + model.innerSpacing
                VStack(spacing: model.innerSpacing) {
                    TimeWarpWheelScroller(model: wheelModel)

                    if let doneAction = model.onDoneTapped {
                        HStack {
                            Spacer()
                            Button(action: doneAction) {
                                HStack(spacing: 6) {
                                    Text(model.doneLabel)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .tracking(1.2)
                                        .textCase(.uppercase)
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(model.doneForeground)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, model.horizontalPadding)
                    }
                }
                .padding(.top, model.innerSpacing)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .drawer(naturalHeight: naturalHeight)
                )
            }

            if model.showsEditorsNote {
                EditorsNoteSection(model: model.editorsNote)
                    .padding(.bottom, model.ruleSpacing)
                    .opacity(model.editorsNoteOpacity)
                    .allowsHitTesting(model.editorsNoteIsInteractive)
                    .accessibilityHidden(!model.editorsNoteIsInteractive)
                    .overlay(scrimOverlay(action: model.editorsNoteScrimAction))
            }

            BriefTabSection(model: model.tabSection)
                .opacity(model.tabSectionOpacity)
                .allowsHitTesting(model.tabSectionIsInteractive)
                .accessibilityHidden(!model.tabSectionIsInteractive)
        }
    }

    /// Transparent tap-target overlay used to dismiss the wheel when the
    /// user taps a faded (non-focal) area. Returns an empty view when no
    /// scrim action is supplied.
    @ViewBuilder
    private func scrimOverlay(action: (() -> Void)?) -> some View {
        if let action {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { action() }
        }
    }
}

// MARK: - Model

extension HomeDailyBrief {
    struct Model {
        let metaRow: BriefMetaRow.Model
        let dateBlock: MastheadDateBlock.Model
        let onDateTapped: () -> Void
        /// Time Warp wheel — present iff the wheel is open. The wiring view
        /// passes nil while closed so the wheel is not built every render.
        let timeWarpWheel: TimeWarpWheelScroller.Model?
        /// Optional chevron + label pill rendered after the date.
        let mastheadPill: MastheadPill.Model?
        /// Action that warps back to today. `nil` when the user is already on
        /// today; the view hides the button in that case.
        let backToTodayAction: (() -> Void)?
        /// Localized label rendered in the back-to-today button (e.g. "Today").
        let backToTodayLabel: String
        /// Action fired by the Done↑ affordance below the wheel. `nil` when
        /// the wheel is closed (the button is hidden).
        let onDoneTapped: (() -> Void)?
        let doneLabel: String
        let doneForeground: Color
        /// Height of the Done↑ row beneath the wheel, used to compute the
        /// drawer transition's natural height.
        let doneRowHeight: CGFloat
        /// Locale-aware long-form date used as the masthead button's
        /// VoiceOver label (e.g. "Monday, May 18, 2026").
        let mastheadAccessibilityLabel: String
        /// VoiceOver hint for the masthead button.
        let mastheadAccessibilityHint: String
        let lede: BriefLede.Model
        let editorsNote: EditorsNoteSection.Model
        /// The tab-based content section — replaces the legacy counts bar +
        /// highlights list. Owns the activeBriefTab state via the model
        /// (resolved by the wiring view from `HomeFeature.State`).
        let tabSection: BriefTabSection.Model
        let horizontalPadding: CGFloat
        let sectionSpacing: CGFloat
        let innerSpacing: CGFloat
        let ruleSpacing: CGFloat

        // MARK: Per-section visibility / interactivity
        //
        // Each section carries its own resolved flags so the view body has
        // no conditional rendering. Wheel mode is encoded entirely by the
        // adapter when it builds the Model — the view stays declarative.

        let metaRowOpacity: Double
        let metaRowIsInteractive: Bool
        /// Non-nil scrim action makes the meta row a wheel-dismiss tap target.
        /// Nil when the wheel is closed (no scrim needed).
        let metaRowScrimAction: (() -> Void)?

        /// Whether the editor's note renders at all. Removed from the tree
        /// in wheel mode so it doesn't reserve its tall height as an empty
        /// gap above the tab strip.
        let showsEditorsNote: Bool
        let editorsNoteOpacity: Double
        let editorsNoteIsInteractive: Bool
        /// Non-nil scrim action makes the editor's note a wheel-dismiss tap
        /// target. Nil when the wheel is closed.
        let editorsNoteScrimAction: (() -> Void)?

        /// Tab section is focal in wheel mode (full opacity, interactive)
        /// and follows non-focal fading when the wheel is closed. Never
        /// gets a scrim — its own tap handlers stay live.
        let tabSectionOpacity: Double
        let tabSectionIsInteractive: Bool
    }
}

// MARK: - Model init

extension HomeDailyBrief.Model {
    init(
        metaRow: BriefMetaRow.Model,
        dateBlock: MastheadDateBlock.Model,
        onDateTapped: @escaping () -> Void,
        timeWarpWheel: TimeWarpWheelScroller.Model?,
        mastheadPill: MastheadPill.Model? = nil,
        mastheadAccessibilityLabel: String = "",
        mastheadAccessibilityHint: String = "",
        backToTodayAction: (() -> Void)? = nil,
        onDoneTapped: (() -> Void)? = nil,
        onScrimTap: (() -> Void)? = nil,
        lede: BriefLede.Model,
        editorsNote: EditorsNoteSection.Model,
        tabSection: BriefTabSection.Model,
        nonFocalOpacity: Double = 1.0,
        nonFocalIsInteractive: Bool = true,
        isWheelMode: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.metaRow = metaRow
        self.dateBlock = dateBlock
        self.onDateTapped = onDateTapped
        self.timeWarpWheel = timeWarpWheel
        self.mastheadPill = mastheadPill
        self.mastheadAccessibilityLabel = mastheadAccessibilityLabel
        self.mastheadAccessibilityHint = mastheadAccessibilityHint
        self.backToTodayAction = backToTodayAction
        self.backToTodayLabel = AppStrings.Home.today
        self.onDoneTapped = onDoneTapped
        self.doneLabel = AppStrings.Common.done
        self.doneForeground = ds.colors.ink
        self.doneRowHeight = 30
        self.lede = lede
        self.editorsNote = editorsNote
        self.tabSection = tabSection
        self.horizontalPadding = ds.spacing.lg
        self.sectionSpacing = ds.spacing.md
        self.innerSpacing = ds.spacing.sm
        // 24pt (lg) gap below the editor's note before the tab strip
        // begins. 16pt was too tight; the masthead → editorial gap above
        // perceives as larger because of the masthead's descenders, so
        // editorial → tab needs more physical space to match visually.
        self.ruleSpacing = ds.spacing.lg

        // Per-section flag resolution.
        //
        // Wheel mode: meta row + editor's note fade out (opacity 0) but
        // stay in the layout so neighboring sections don't slide. Tabs
        // promote to focal: full opacity, fully interactive, no scrim.
        //
        // Closed: every section follows the umbrella nonFocal* values so
        // the existing scrim-and-fade overlay treatment continues to work
        // for non-wheel modals that need the same affordance.
        self.metaRowOpacity = isWheelMode ? 0 : nonFocalOpacity
        self.metaRowIsInteractive = isWheelMode ? false : nonFocalIsInteractive
        self.metaRowScrimAction = onScrimTap

        // Hide the editor's note when either:
        //  • wheel mode is active (the wheel is the focal surface)
        //  • there are no paragraphs (Foundation Models couldn't
        //    produce a brief — see `localization_edd.md §5`).
        // The tabs below continue rendering events / reminders /
        // birthdays regardless; the editor's note is editorial
        // commentary, not the data itself.
        self.showsEditorsNote = !isWheelMode && !editorsNote.paragraphs.isEmpty
        self.editorsNoteOpacity = nonFocalOpacity
        self.editorsNoteIsInteractive = nonFocalIsInteractive
        self.editorsNoteScrimAction = onScrimTap

        self.tabSectionOpacity = isWheelMode ? 1.0 : nonFocalOpacity
        self.tabSectionIsInteractive = isWheelMode ? true : nonFocalIsInteractive
    }
}
