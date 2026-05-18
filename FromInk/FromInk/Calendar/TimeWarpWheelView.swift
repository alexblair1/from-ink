import SwiftUI

/// The Time Warp wheel — a horizontal strip of `DayCellView`s with a stationary
/// center pointer, a horizontal baseline rule running through the cell baselines,
/// and a soft fade mask at the left and right edges.
///
/// This is the **stateless layout** of the wheel: given a list of dates and one
/// selected date, the wheel positions the selected cell at horizontal center
/// and renders everything else around it. Scroll, snap, haptics, and the
/// open/close transition belong to a separate interactive wrapper (next PR).
///
/// Composition (top → bottom of z-stack):
/// 1. Horizontal baseline rule at the tick-bottom anchor (`baselineRuleTopOffset`).
///    The 1pt baseline-marker dot inside each `DayCellView` sits **on** this rule.
/// 2. Horizontal strip of `DayCellView`s, offset so the selected cell sits at
///    the wheel's horizontal center.
/// 3. Center pointer: a faint vertical rule + a top "notch" (▼) + a bottom
///    "notch" (▲) at the horizontal center.
///
/// The whole thing is masked by a linear gradient so distant cells dissolve
/// rather than getting clipped sharply.
///
struct TimeWarpWheelView: View {
    let model: Model

    var body: some View {
        ZStack(alignment: .top) {
            baselineRule
            cellsStrip
            centerPointer
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.height)
        .mask(edgeFadeMask)
    }

    private var baselineRule: some View {
        Rectangle()
            .fill(model.baselineRuleColor)
            .opacity(model.baselineRuleOpacity)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.top, model.baselineRuleTopOffset)
    }

    private var cellsStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.cells.enumerated()), id: \.offset) { _, cell in
                DayCellView(model: cell)
            }
        }
        .offset(x: model.stripOffsetX)
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
}

// MARK: - NotchShape

/// A small isoceles triangle used for the top and bottom center-pointer
/// notches. `.down` points its apex toward the wheel; `.up` does the inverse.
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

extension TimeWarpWheelView {
    struct Model: Equatable {
        // Wheel geometry
        let height: CGFloat
        let baselineRuleTopOffset: CGFloat
        let baselineRuleColor: Color
        let baselineRuleOpacity: Double
        // Edge fade mask — fraction-of-width stops
        let edgeFadeStart: CGFloat
        let edgeFadeEnd: CGFloat
        // Center pointer
        let centerRuleColor: Color
        let centerRuleOpacity: Double
        let notchColor: Color
        let notchWidth: CGFloat
        let notchHeight: CGFloat
        // Cells — already resolved, centered on the selected one
        let cells: [DayCellView.Model]
        let stripOffsetX: CGFloat
    }
}

// MARK: - Device variant

extension TimeWarpWheelView.Model {
    enum Device {
        case iPad
        case iPhone

        var cellDevice: DayCellView.Model.Device {
            switch self {
            case .iPad:   return .iPad
            case .iPhone: return .iPhone
            }
        }

        /// Width of each cell — matches `DayCellView` per-device sizing.
        var cellWidth: CGFloat {
            switch self {
            case .iPad:   return 56
            case .iPhone: return 44
            }
        }

        /// Distance from the top of the wheel to the baseline rule. This is
        /// the tick-bottom anchor inside `DayCellView`: `paddingTop +
        /// tickReservedHeight`. iPad = 14 + 28 = 42. iPhone = 10 + 22 = 32.
        var baselineRuleTopOffset: CGFloat {
            switch self {
            case .iPad:   return 42
            case .iPhone: return 32
            }
        }

        /// Total wheel height — gives enough breathing room below the
        /// today/this-wk label without clipping the bottom notch.
        var wheelHeight: CGFloat {
            switch self {
            case .iPad:   return 120
            case .iPhone: return 96
            }
        }

        var notchWidth: CGFloat {
            switch self {
            case .iPad:   return 12
            case .iPhone: return 10
            }
        }

        var notchHeight: CGFloat {
            switch self {
            case .iPad:   return 8
            case .iPhone: return 7
            }
        }
    }
}

// MARK: - Model init

extension TimeWarpWheelView.Model {

    /// Convenience init that materialises the strip from a date list and the
    /// user's `Calendar` / `Locale`. Cell models are pre-resolved here so the
    /// view body has nothing to derive.
    ///
    /// `selectedDate` must appear in `dates` (matched by `Calendar.isDate(_,
    /// inSameDayAs:)`); if it does not, the strip falls back to the natural
    /// center (`dates.count / 2`) — a quiet failure that keeps the view
    /// rendering rather than crashing in production.
    ///
    /// - Parameters:
    ///   - device: iPad vs iPhone sizing.
    ///   - dates: Ordered list of dates the wheel renders. Length must be odd
    ///     for the natural-center fallback to land on a real cell — callers
    ///     should pass `2 * range + 1` dates.
    ///   - selectedDate: The date currently at the wheel's center. The strip
    ///     is offset so this cell sits at the horizontal center of the wheel.
    ///   - today: The user's current local day, forwarded into each cell.
    ///   - calendar: User's `Calendar` (from `CalendarContext.userCalendar()`).
    ///   - locale: User's `Locale` (from `CalendarContext.userLocale()`).
    ///   - ds: Design system token bundle.
    init(
        device: Device,
        dates: [Date],
        selectedDate: Date,
        today: Date,
        calendar: Calendar,
        locale: Locale,
        ds: DesignSystem = .standard
    ) {
        var cal = calendar
        cal.locale = locale

        let selectedIndex = dates.firstIndex { cal.isDate($0, inSameDayAs: selectedDate) }
            ?? dates.count / 2

        self.cells = dates.enumerated().map { offset, date in
            let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
            let distance = abs(offset - selectedIndex)
            return DayCellView.Model(
                device: device.cellDevice,
                date: date,
                today: today,
                calendar: calendar,
                locale: locale,
                isSelected: isSelected,
                distanceFromSelection: distance,
                ds: ds
            )
        }

        // Strip is centered in the ZStack by default — the cell at the
        // natural center index sits at wheel-center. We push the strip so
        // `selectedIndex` lands there instead.
        let naturalCenterIndex = (dates.count - 1) / 2
        self.stripOffsetX = CGFloat(naturalCenterIndex - selectedIndex) * device.cellWidth

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
