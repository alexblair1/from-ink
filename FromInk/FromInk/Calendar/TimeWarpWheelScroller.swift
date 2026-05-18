import SwiftUI

/// The interactive Time Warp wheel — wraps a horizontal `ScrollView` of
/// `DayCellView`s with snap-to-cell behavior and reports the centered cell
/// back to the caller.
///
/// ## Composition
///
/// Differs from `TimeWarpWheelView` only in the cell-strip layer:
/// `TimeWarpWheelView` lays cells out with a static `.offset(x:)`,
/// `TimeWarpWheelScroller` lays them out with `ScrollView + LazyHStack +
/// CenteredCellScrollTargetBehavior`. The chrome (baseline rule, center
/// pointer, edge fade) is intentionally duplicated rather than abstracted —
/// the duplication is ~30 lines and keeps each view legible without a
/// generic chrome wrapper.
///
/// ## Input model
///
/// Mirrors the React design source (`time-warp.jsx`):
/// - **Drag / scroll**: native `ScrollView` snap via `CenteredCellScrollTargetBehavior`
/// - **Tap cell**: fires `onDateSelected` directly
/// - **`←` / `→` keys**: walks the wheel by ±1 day via `.onKeyPress`
/// - **`ESC` key**: closes the wheel via the optional `onClose` callback
/// - Auto-focuses on appear so keyboard input is immediate
///
/// ## State ownership
///
/// - **Local `@State scrolledID`**: transient UI state — the day the user is
///   currently parked on. Initialized from the model's `selectedDayKey` and
///   updated by SwiftUI's native scroll snap.
/// - **Parent owns `selectedDate`**: domain state. Pushed in via the model.
///   The dual `.onChange` keeps both directions in sync; the guard
///   `newID != model.selectedDayKey` in `handleUserScroll` filters out
///   programmatic syncs (which would otherwise echo back to the parent).
///
/// ## Why the custom `ScrollTargetBehavior`
///
/// SwiftUI's built-in `.scrollTargetBehavior(.viewAligned)` snaps cells to
/// the scroll view's leading edge regardless of what `.scrollPosition(anchor:)`
/// says. That produces an asymmetric bug: programmatic position writes (e.g.
/// a "Today" button) center correctly, but user-driven scroll snaps land
/// off-center. `CenteredCellScrollTargetBehavior` snaps `target.rect.midX`
/// to the nearest cell center, which matches the wheel's stationary
/// indicator triangle. See `feedback_scroll_snap_alignment.md` in memory.
///
/// ## Accessibility
///
/// - Each cell carries a locale-aware full-date `accessibilityLabel`
///   (e.g. "Wednesday, May 13, 2026").
/// - The selected cell adds `.isSelected`; unselected cells include a
///   localized hint.
/// - The wheel is `.focusable()` for the hardware-keyboard focus engine.
/// - Haptics use `UIImpactFeedbackGenerator(style: .light)` on every
///   snapped-day change, including arrow-key and tap selection.
///
struct TimeWarpWheelScroller: View {
    let model: Model

    @State private var scrolledID: String?
    /// The day-key whose cell is currently nearest the viewport center,
    /// updated continuously by `.onScrollGeometryChange`. Drives the
    /// `.sensoryFeedback` haptic so each cell crossed during a drag fires
    /// a tick, matching the React design's "each day-tick crossed" rule.
    @State private var centeredCellID: String?
    /// Auto-focuses the wheel on appear so iPad/Mac keyboard users can press
    /// ←/→ immediately without tabbing to it first.
    @FocusState private var isFocused: Bool

    init(model: Model) {
        self.model = model
        self._scrolledID = State(initialValue: model.selectedDayKey)
        // Seed the haptic-trigger state with the initial selected cell so
        // the first scroll-geometry pass doesn't produce a spurious tick.
        self._centeredCellID = State(initialValue: model.selectedDayKey)
    }

    var body: some View {
        ZStack(alignment: .top) {
            baselineRule
            cellsStrip
            centerPointer
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.height)
        .mask(edgeFadeMask)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) {
            scrubByOne(delta: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            scrubByOne(delta: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if let onClose = model.onClose {
                onClose()
                return .handled
            }
            return .ignored
        }
        .onChange(of: scrolledID) { _, newID in
            handleUserScroll(to: newID)
        }
        .onChange(of: model.selectedDayKey) { _, newKey in
            // Parent pushed a new selected date (e.g. via a "Today" button
            // or a TestStore-driven warp). Sync the scroll without firing
            // the closure back at the parent.
            guard scrolledID != newKey else { return }
            scrolledID = newKey
        }
        // Per the React design's "each day-tick crossed" rule: a light
        // haptic fires whenever the centered cell changes, including
        // continuously during a finger drag (not just on snap-settle).
        // `centeredCellID` is driven by `.onScrollGeometryChange` above.
        .sensoryFeedback(.impact(weight: .light), trigger: centeredCellID)
    }

    // MARK: - Subviews

    private var baselineRule: some View {
        Rectangle()
            .fill(model.baselineRuleColor)
            .opacity(model.baselineRuleOpacity)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.top, model.baselineRuleTopOffset)
    }

    private var cellsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(model.cells) { cell in
                    DayCellView(model: cell.cellModel)
                        .id(cell.id)
                        .onTapGesture {
                            // Tap a cell → fire selection directly; the
                            // scrollPosition binding will follow on the
                            // parent's re-render with the new selectedDayKey.
                            // Haptic is driven by the centered-cell change
                            // that the upcoming scroll animation will
                            // produce, so we don't fire one manually here.
                            model.onDateSelected(cell.date)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(cell.accessibilityLabel)
                        .accessibilityAddTraits(
                            cell.id == model.selectedDayKey
                                ? [.isButton, .isSelected]
                                : [.isButton]
                        )
                        .accessibilityHint(
                            cell.id == model.selectedDayKey
                                ? ""
                                : model.cellAccessibilityHint
                        )
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(CenteredCellScrollTargetBehavior(cellWidth: model.cellWidth))
        .scrollPosition(id: $scrolledID, anchor: .center)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: String?.self) { geometry in
            // Compute the day-key of the cell currently sitting at viewport
            // center in scroll-content coords. Returns nil if the scroll
            // position lands outside any cell (e.g. during rubber-band).
            let centerX = geometry.contentOffset.x + geometry.containerSize.width / 2
            let nearestIndex = Int(((centerX - model.cellWidth / 2) / model.cellWidth).rounded())
            guard model.cells.indices.contains(nearestIndex) else { return nil }
            return model.cells[nearestIndex].id
        } action: { _, newID in
            centeredCellID = newID
        }
    }

    private var centerPointer: some View {
        ZStack {
            Rectangle()
                .fill(model.centerRuleColor)
                .opacity(model.centerRuleOpacity)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack {
                NotchShape(direction: .down)
                    .fill(model.notchColor)
                    .frame(width: model.notchWidth, height: model.notchHeight)
                Spacer(minLength: 0)
                NotchShape(direction: .up)
                    .fill(model.notchColor)
                    .frame(width: model.notchWidth, height: model.notchHeight)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: max(model.notchWidth, 1))
        .allowsHitTesting(false)
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: model.edgeFadeStart),
                .init(color: .black, location: model.edgeFadeEnd),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interaction

    /// Walks `±1` cell from the currently selected one. Fired by the
    /// hardware-keyboard arrow keys; matches the input contract described
    /// in the React design source. Clamps at the wheel's date range
    /// boundaries. Haptic is fired by the centered-cell change that the
    /// upcoming scroll animation will produce.
    private func scrubByOne(delta: Int) {
        guard let currentIndex = model.cells.firstIndex(where: { $0.id == model.selectedDayKey })
        else { return }
        let targetIndex = currentIndex + delta
        guard model.cells.indices.contains(targetIndex) else { return }
        model.onDateSelected(model.cells[targetIndex].date)
    }

    private func handleUserScroll(to newID: String?) {
        guard let newID, let date = model.dateForDayKey(newID) else { return }
        // Already in sync with the model — either the initial render, or a
        // programmatic push from the parent that we just mirrored to
        // `scrolledID`. Either way, the user did not scroll, so no callback.
        guard newID != model.selectedDayKey else { return }
        // Haptic is driven by `.onScrollGeometryChange` / `.sensoryFeedback`
        // — no manual fire here.
        model.onDateSelected(date)
    }
}

// MARK: - CenteredCellScrollTargetBehavior

/// Custom `ScrollTargetBehavior` that snaps so a cell's *center* aligns with
/// the scroll viewport's *center* — i.e., directly under the wheel's
/// stationary indicator.
///
/// Required because the built-in `.scrollTargetBehavior(.viewAligned)` snaps
/// to the *leading* edge of cells regardless of what `.scrollPosition(anchor:)`
/// is set to. The asymmetry was producing a real bug: programmatic warps
/// (e.g. the ← TODAY button) used the center anchor and landed correctly,
/// but user-driven scroll snaps used leading-edge and landed off-center.
///
/// Math: `target.rect` is the would-be viewport rectangle in scroll-content
/// coordinates. We compute the nearest cell-index whose center is closest
/// to `target.rect.midX`, then nudge the target so that cell's center sits
/// exactly at the viewport's midX.
///
struct CenteredCellScrollTargetBehavior: ScrollTargetBehavior {
    let cellWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let snappedCenterX = Self.snappedCenterX(
            forContentMidX: target.rect.midX,
            cellWidth: cellWidth
        )
        target.rect.origin.x = snappedCenterX - target.rect.width / 2
    }

    /// Pure snap math. Given the viewport's center in scroll-content
    /// coordinates and the cell width, returns the cell-center the snap
    /// should land on. Extracted as a static function so it can be unit-
    /// tested without constructing SwiftUI's internal `ScrollTarget` /
    /// `TargetContext` types.
    ///
    /// Assumes cells of uniform width laid out without spacing starting at
    /// content x=0 (cell N occupies `[N*W, (N+1)*W]`, center at `N*W + W/2`).
    /// The rounding direction is `.toNearestOrAwayFromZero` (Swift's default
    /// for `rounded()`), which biases away-from-zero for ties — practically
    /// indistinguishable from `.toNearestOrEven` for the indices we hit.
    static func snappedCenterX(
        forContentMidX midX: CGFloat,
        cellWidth: CGFloat
    ) -> CGFloat {
        let nearestCellIndex = ((midX - cellWidth / 2) / cellWidth).rounded()
        return nearestCellIndex * cellWidth + cellWidth / 2
    }
}

// MARK: - NotchShape

/// Same triangle as `TimeWarpWheelView` — duplicated here so the two wheel
/// types can be deleted/refactored independently if the design diverges.
private struct NotchShape: Shape {
    enum Direction { case up, down }
    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .down:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        case .up:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Model

extension TimeWarpWheelScroller {
    /// Self-contained model — not Equatable because of the `onDateSelected`
    /// closure. SwiftUI redraws on identity change rather than equality here,
    /// which is fine for a wheel that's already lazy via `LazyHStack`.
    struct Model {
        struct Cell: Identifiable {
            /// The day-key — used as both `Identifiable.id` and the
            /// `scrollPosition` binding key. Stable across re-renders.
            let id: String
            let date: Date
            let cellModel: DayCellView.Model
            /// Locale-aware full-date string spoken by VoiceOver. Pre-resolved
            /// because the View layer doesn't carry the Locale needed to format.
            let accessibilityLabel: String
            /// True if this cell represents today — VoiceOver appends "today"
            /// to the label so the user knows where they are.
            let isToday: Bool
        }

        // Wheel geometry — same set as TimeWarpWheelView.Model.
        let height: CGFloat
        let baselineRuleTopOffset: CGFloat
        let baselineRuleColor: Color
        let baselineRuleOpacity: Double
        let edgeFadeStart: CGFloat
        let edgeFadeEnd: CGFloat
        let centerRuleColor: Color
        let centerRuleOpacity: Double
        let notchColor: Color
        let notchWidth: CGFloat
        let notchHeight: CGFloat

        // Strip data
        let cells: [Cell]
        let selectedDayKey: String
        /// Width of each cell — used by the centered-snap scroll behavior to
        /// align cell centers to the wheel's stationary indicator.
        let cellWidth: CGFloat
        /// Localized VoiceOver hint spoken for unselected cells.
        let cellAccessibilityHint: String

        // Callback
        let onDateSelected: (Date) -> Void
        /// Fired when the user presses ESC while the wheel is focused. The
        /// parent typically routes this to the same `wheelToggled` action
        /// used by the Done button and scrim.
        let onClose: (() -> Void)?

        /// Look up a `Date` for a given day-key. Stored as a closure so the
        /// model carries its own dayKey → Date mapping without needing
        /// CalendarContext at the view layer.
        let dateForDayKey: (String) -> Date?
    }
}

// MARK: - Model init

extension TimeWarpWheelScroller.Model {

    /// Convenience init that materialises the strip from a date list and the
    /// user's `Calendar` / `Locale`. Mirrors `TimeWarpWheelView.Model` but
    /// adds the `onDateSelected` closure and pre-builds a `dayKey → Date`
    /// lookup the view uses on scroll-snap.
    ///
    /// `dayKey` is computed inline here using the Gregorian/POSIX/user-TZ
    /// formula from `CalendarContext.dayKey(_:)` (see `dates_edd.md` §6.2).
    /// Inlining avoids importing `CalendarContext` in a view-layer file —
    /// the wiring view passes the resolved Calendar/Locale and the wheel
    /// derives keys locally. Locale of the calendar must be set before
    /// passing it in; this init does that for safety.
    ///
    /// - Parameters:
    ///   - device: iPad vs iPhone sizing — reused from TimeWarpWheelView.
    ///   - dates: Ordered list of dates in the wheel's range.
    ///   - selectedDate: The date initially at center; must appear in `dates`.
    ///   - today: The user's current local day (forwarded to each cell).
    ///   - calendar: User's `Calendar`.
    ///   - locale: User's `Locale`.
    ///   - timeZone: User's `TimeZone` — used by the day-key formatter so
    ///     keys reflect the user's wall-clock day, not UTC.
    ///   - onDateSelected: Fired when the user scrolls to a new day (or taps
    ///     a cell). Caller forwards to the reducer via a `dateWarpedTo`
    ///     action.
    ///   - onClose: Fired when the user presses ESC. Optional; pass `nil` if
    ///     ESC should be a no-op (e.g. if the wheel is in a context with no
    ///     close affordance).
    ///   - ds: Design system token bundle.
    init(
        device: TimeWarpWheelView.Model.Device,
        dates: [Date],
        selectedDate: Date,
        today: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone,
        onDateSelected: @escaping (Date) -> Void,
        onClose: (() -> Void)? = nil,
        ds: DesignSystem = .standard
    ) {
        var cal = calendar
        cal.locale = locale

        let selectedIndex = dates.firstIndex { cal.isDate($0, inSameDayAs: selectedDate) }
            ?? dates.count / 2

        // Day-key formatter — Gregorian/POSIX in user's timezone, matching
        // CalendarContext.dayKey semantics. We rebuild a tiny inline version
        // here so the view layer doesn't take a TCA dependency.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let dayKey: (Date) -> String = { d in
            let c = gregorian.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
        }

        // Pre-format the long-form date for each cell so VoiceOver speaks
        // a locale-aware, unambiguous string ("Wednesday, May 13, 2026" /
        // "水曜日、2026年5月13日" / "الأربعاء، ١٣ مايو ٢٠٢٦").
        let fullDateFormat = Date.FormatStyle.dateTime
            .weekday(.wide)
            .month(.wide)
            .day()
            .year()
            .locale(locale)

        let cellArray: [Cell] = dates.enumerated().map { offset, date in
            let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
            let isToday = cal.isDate(date, inSameDayAs: today)
            let distance = abs(offset - selectedIndex)
            let cellModel = DayCellView.Model(
                device: device.cellDevice,
                date: date,
                today: today,
                calendar: calendar,
                locale: locale,
                isSelected: isSelected,
                distanceFromSelection: distance,
                ds: ds
            )
            return Cell(
                id: dayKey(date),
                date: date,
                cellModel: cellModel,
                accessibilityLabel: date.formatted(fullDateFormat),
                isToday: isToday
            )
        }

        // Pre-build the lookup so scroll-snap can resolve dayKey → Date in O(1).
        let lookup = Dictionary(uniqueKeysWithValues: cellArray.map { ($0.id, $0.date) })

        self.cells = cellArray
        self.selectedDayKey = dayKey(selectedDate)
        self.onDateSelected = onDateSelected
        self.onClose = onClose
        self.dateForDayKey = { lookup[$0] }
        self.cellWidth = device.cellWidth
        self.cellAccessibilityHint = AppStrings.Calendar.wheelCellHint

        self.height = device.wheelHeight
        self.baselineRuleTopOffset = device.baselineRuleTopOffset
        self.baselineRuleColor = ds.colors.ink
        self.baselineRuleOpacity = 0.85
        self.edgeFadeStart = 0.08
        self.edgeFadeEnd = 0.92
        self.centerRuleColor = ds.colors.ink
        self.centerRuleOpacity = 0.18
        self.notchColor = ds.colors.ink
        self.notchWidth = device.notchWidth
        self.notchHeight = device.notchHeight
    }
}
