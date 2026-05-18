import SwiftUI

/// A single day cell inside the Time Warp wheel.
///
/// Composes (top → bottom): a bottom-anchored vertical tick, an optional 1pt
/// baseline marker dot (iPad only), the day-of-week letter, the day number,
/// and an optional "TODAY" mini-label (iPad only). Tick height encodes
/// hierarchy — today > week-start (Mon) > weekday > weekend.
///
/// Stateless Component view. The Model holds resolved visual values; the view
/// branches on nothing.
///
struct DayCellView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            // Tick column — fixed reserved height, bottom-anchored so the
            // tick's baseline aligns across cells regardless of tick height.
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: model.tickReservedHeight)
                Rectangle()
                    .fill(model.tickColor)
                    .frame(width: model.tickWidth, height: model.tickHeight)
            }
            .padding(.bottom, model.tickBottomSpacing)

            // 1pt baseline marker dot — iPad only.
            if let baselineSpacing = model.baselineMarkerBottomSpacing {
                Rectangle()
                    .fill(model.tickColor)
                    .frame(width: 1, height: 1)
                    .padding(.bottom, baselineSpacing)
            }

            // Day-of-week letter.
            Text(model.dayLetter)
                .font(model.dayLetterFont)
                .tracking(model.dayLetterTracking)
                .foregroundStyle(model.dayLetterColor)
                .textCase(.uppercase)

            // Day number — fixed-height row so the baseline doesn't shift
            // when type scales between unselected and selected sizes.
            Text(model.dayNumber)
                .font(model.dayNumberFont)
                .italic(model.dayNumberItalic)
                .monospacedDigit()
                .foregroundStyle(model.dayNumberColor)
                .frame(height: model.dayNumberHeight)
                .padding(.top, model.dayNumberTopSpacing)

            // "TODAY" mini-label — iPad only, shown when isToday && !isSelected.
            if let label = model.todayLabel,
               let font = model.todayLabelFont,
               let tracking = model.todayLabelTracking,
               let color = model.todayLabelColor,
               let topSpacing = model.todayLabelTopSpacing {
                Text(label)
                    .font(font)
                    .tracking(tracking)
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                    .frame(height: 9)
                    .padding(.top, topSpacing)
            }
        }
        .frame(width: model.cellWidth)
        .padding(.top, model.paddingTop)
        .opacity(model.opacity)
    }
}

// MARK: - Model

extension DayCellView {
    struct Model: Equatable {
        // Layout
        let cellWidth: CGFloat
        let paddingTop: CGFloat
        // Tick
        let tickHeight: CGFloat
        let tickWidth: CGFloat
        let tickReservedHeight: CGFloat
        let tickBottomSpacing: CGFloat
        let tickColor: Color
        // Baseline marker (nil = hidden)
        let baselineMarkerBottomSpacing: CGFloat?
        // Day-of-week letter
        let dayLetter: String
        let dayLetterFont: Font
        let dayLetterTracking: CGFloat
        let dayLetterColor: Color
        // Day number
        let dayNumber: String
        let dayNumberFont: Font
        let dayNumberHeight: CGFloat
        let dayNumberColor: Color
        let dayNumberItalic: Bool
        let dayNumberTopSpacing: CGFloat
        // "TODAY" mini-label (nil = hidden)
        let todayLabel: String?
        let todayLabelFont: Font?
        let todayLabelTracking: CGFloat?
        let todayLabelColor: Color?
        let todayLabelTopSpacing: CGFloat?
        // State
        let opacity: Double
    }
}

// MARK: - Device variant

extension DayCellView.Model {
    enum Device {
        case iPad
        case iPhone
    }
}

// MARK: - Model init

extension DayCellView.Model {

    /// Convenience init that resolves all visual values from semantic inputs.
    ///
    /// - Parameters:
    ///   - device: Selects iPad (56pt cell) or iPhone (44pt cell) sizing.
    ///   - dayLetter: Single character for the day-of-week (e.g. "T").
    ///   - dayNumber: Day-of-month as a string (e.g. "6").
    ///   - isToday: Whether this cell represents today's date.
    ///   - isWeekStart: Whether this cell is a Monday (start of week).
    ///   - isWeekend: Whether this cell is a Saturday or Sunday.
    ///   - isSelected: Whether this cell is currently centered under the pointer.
    ///   - distanceFromSelection: Absolute distance in cells from the selected cell — drives the opacity falloff so far-away cells fade out toward the mask edges.
    ///   - ds: Design system token bundle.
    init(
        device: Device,
        dayLetter: String,
        dayNumber: String,
        isToday: Bool,
        isWeekStart: Bool,
        isWeekend: Bool,
        isSelected: Bool,
        distanceFromSelection: Int,
        ds: DesignSystem = .standard
    ) {
        let distance = max(0, distanceFromSelection)
        switch device {
        case .iPad:
            self.cellWidth = 56
            self.paddingTop = 14
            self.tickReservedHeight = 28
            self.tickBottomSpacing = 6
            self.tickHeight = isToday ? 28 : isWeekStart ? 24 : isWeekend ? 12 : 18
            self.tickWidth = isSelected ? 2 : (isToday || isWeekStart ? 1.5 : 1)
            self.tickColor = ds.colors.ink
            self.baselineMarkerBottomSpacing = 8
            self.dayLetter = dayLetter
            self.dayLetterFont = .system(size: 9.5, weight: .medium, design: .monospaced)
            self.dayLetterTracking = 1.2
            self.dayLetterColor = isWeekend ? ds.colors.ink3 : ds.colors.ink2
            self.dayNumber = dayNumber
            self.dayNumberFont = .system(size: isSelected ? 20 : 14, weight: .regular, design: .serif)
            self.dayNumberHeight = 22
            self.dayNumberColor = ds.colors.ink
            self.dayNumberItalic = isToday && !isSelected
            self.dayNumberTopSpacing = 4
            let showTodayLabel = isToday && !isSelected
            self.todayLabel = showTodayLabel ? "today" : nil
            self.todayLabelFont = showTodayLabel ? .system(size: 7.5, weight: .medium, design: .monospaced) : nil
            self.todayLabelTracking = showTodayLabel ? 0.8 : nil
            self.todayLabelColor = showTodayLabel ? ds.colors.ink3 : nil
            self.todayLabelTopSpacing = showTodayLabel ? 4 : nil
            self.opacity = isSelected ? 1 : max(0.22, 1 - Double(distance) * 0.045)

        case .iPhone:
            self.cellWidth = 44
            self.paddingTop = 10
            self.tickReservedHeight = 22
            self.tickBottomSpacing = 5
            self.tickHeight = isToday ? 22 : isWeekStart ? 18 : isWeekend ? 10 : 14
            self.tickWidth = isSelected ? 2 : (isToday || isWeekStart ? 1.5 : 1)
            self.tickColor = ds.colors.ink
            self.baselineMarkerBottomSpacing = nil
            self.dayLetter = dayLetter
            self.dayLetterFont = .system(size: 8.5, weight: .medium, design: .monospaced)
            self.dayLetterTracking = 1.1
            self.dayLetterColor = isWeekend ? ds.colors.ink3 : ds.colors.ink2
            self.dayNumber = dayNumber
            self.dayNumberFont = .system(size: isSelected ? 17 : 12, weight: .regular, design: .serif)
            self.dayNumberHeight = 18
            self.dayNumberColor = ds.colors.ink
            self.dayNumberItalic = isToday && !isSelected
            self.dayNumberTopSpacing = 3
            self.todayLabel = nil
            self.todayLabelFont = nil
            self.todayLabelTracking = nil
            self.todayLabelColor = nil
            self.todayLabelTopSpacing = nil
            self.opacity = isSelected ? 1 : max(0.22, 1 - Double(distance) * 0.05)
        }
    }
}
