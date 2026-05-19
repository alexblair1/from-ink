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
struct HomeDailyBrief: View {
    let model: Model

    /// Honors the system "Reduce Motion" accessibility setting. When true,
    /// the wheel drawer falls back to a simple opacity fade rather than the
    /// height-clip drawer animation — required by Apple HIG.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Non-focal top strip
            BriefMetaRow(model: model.metaRow)
                .padding(.top, model.sectionSpacing)
                .opacity(model.nonFocalOpacity)
                .allowsHitTesting(model.nonFocalIsInteractive)
                .accessibilityHidden(!model.nonFocalIsInteractive)
                .overlay(scrimOverlay(action: model.onScrimTap))

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

            // Non-focal — editorial note + tab section.
            //
            // No HairlineRule between the editor's note and the tab strip —
            // the strip's per-tab top rules provide the boundary (with a
            // negative-space break above the active tab so it reads as
            // "raised into" the body above).
            Group {
                EditorsNoteSection(model: model.editorsNote)
                    .padding(.bottom, model.ruleSpacing)

                BriefTabSection(model: model.tabSection)
            }
            .opacity(model.nonFocalOpacity)
            .allowsHitTesting(model.nonFocalIsInteractive)
            .accessibilityHidden(!model.nonFocalIsInteractive)
            .overlay(scrimOverlay(action: model.onScrimTap))
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
        /// Action fired when the user taps a faded non-focal section to
        /// dismiss the wheel. `nil` when no scrim should be active.
        let onScrimTap: (() -> Void)?
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
        /// Opacity for non-focal subsections. Faded while the wheel is open.
        let nonFocalOpacity: Double
        /// Whether non-focal subsections accept hit-testing.
        let nonFocalIsInteractive: Bool
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
        self.onScrimTap = onScrimTap
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
        self.nonFocalOpacity = nonFocalOpacity
        self.nonFocalIsInteractive = nonFocalIsInteractive
    }
}
