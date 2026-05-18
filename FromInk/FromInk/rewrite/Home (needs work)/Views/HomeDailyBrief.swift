import SwiftUI

/// The daily brief section: meta row, date, lede, counts bar, and expandable content.
/// Feature view — no TCA imports.
///
struct HomeDailyBrief: View {
    let model: Model
    @Binding var isExpanded: Bool

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

            // Focal — the wheel itself + optional Done button below.
            //
            // `.transition(.drawer(naturalHeight:))` is the only animation
            // primitive that actually grows the layout slot: it animates
            // a frame-height clip from 0 to the wheel's natural height,
            // anchored at the top. Content below the wheel slot pushes
            // down smoothly with the slot's growth.
            //
            // SwiftUI's built-in `.move(edge: .top)` and `.push(from: .top)`
            // both translate visually but keep the slot at full height
            // throughout the animation, leaving an empty gap below the
            // sliding wheel until it lands. See `DrawerTransition.swift`.
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

            // Non-focal — brief body
            Group {
                EditorsNoteSection(model: model.editorsNote)

                HairlineRule()
                    .padding(.top, model.ruleSpacing)
                    .padding(.horizontal, model.horizontalPadding)

                BriefCountsBar(model: model.countsBar)

                HairlineRule()
                    .padding(.horizontal, model.horizontalPadding)

                // Expanded content — events calendar
                if isExpanded {
                    highlightsSection

                    BriefFooterActions(model: model.footerActions)

                    HairlineRule()
                        .padding(.top, model.ruleSpacing)
                        .padding(.horizontal, model.horizontalPadding)
                }
            }
            .opacity(model.nonFocalOpacity)
            .allowsHitTesting(model.nonFocalIsInteractive)
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

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(
                Array(model.highlights.enumerated()),
                id: \.element.id
            ) { index, highlight in
                if index > 0 {
                    HairlineRule()
                }
                HighlightRow(model: highlight)
            }
        }
        .padding(.horizontal, model.horizontalPadding)
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
        /// Optional chevron + label pill rendered after the date. The pill
        /// labels the wheel disclosure when closed and signals warp distance
        /// (e.g. "3 days ago") when warped.
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
        /// drawer transition's natural height. Resolved in the Model init.
        let doneRowHeight: CGFloat
        /// Locale-aware long-form date used as the masthead button's
        /// VoiceOver label (e.g. "Monday, May 18, 2026").
        let mastheadAccessibilityLabel: String
        /// VoiceOver hint for the masthead button. State-dependent:
        /// `"…open the date scrub wheel"` when closed,
        /// `"…close the date scrub wheel"` when open.
        let mastheadAccessibilityHint: String
        let lede: BriefLede.Model
        let countsBar: BriefCountsBar.Model
        let editorsNote: EditorsNoteSection.Model
        let highlights: [HighlightRow.Model]
        let footerActions: BriefFooterActions.Model
        let highlightsLabel: String
        let highlightsLabelColor: Color
        let horizontalPadding: CGFloat
        let sectionSpacing: CGFloat
        let innerSpacing: CGFloat
        let ruleSpacing: CGFloat
        /// Opacity for non-focal subsections (BriefMetaRow + EditorsNote +
        /// counts + footer). Faded while the wheel is open.
        let nonFocalOpacity: Double
        /// Whether non-focal subsections accept hit-testing. Disabled while
        /// the wheel is open.
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
        countsBar: BriefCountsBar.Model,
        editorsNote: EditorsNoteSection.Model,
        highlights: [HighlightRow.Model],
        footerActions: BriefFooterActions.Model,
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
        // Mono 10pt label + small SF Symbol + ~10pt vertical breathing room
        // = ~30pt. The constant doesn't need to be exact — slight over-
        // estimation just leaves a couple of pixels of empty space below
        // the Done button when the drawer is fully open.
        self.doneRowHeight = 30
        self.lede = lede
        self.countsBar = countsBar
        self.editorsNote = editorsNote
        self.highlights = highlights
        self.footerActions = footerActions
        self.highlightsLabel = AppStrings.Home.highlights
        self.highlightsLabelColor = ds.colors.ink2
        self.horizontalPadding = ds.spacing.lg
        self.sectionSpacing = ds.spacing.md
        self.innerSpacing = ds.spacing.sm
        self.ruleSpacing = ds.spacing.base
        self.nonFocalOpacity = nonFocalOpacity
        self.nonFocalIsInteractive = nonFocalIsInteractive
    }
}
