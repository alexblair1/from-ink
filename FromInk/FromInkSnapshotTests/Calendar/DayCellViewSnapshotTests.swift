import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for the Time Warp wheel's `DayCellView`.
///
/// Captures every visual state the Model can resolve to, on both
/// device size variants (iPad 56pt cells, iPhone 44pt cells).
///
/// Each test pins `.colorScheme(.light)` so the asset-catalog `ink/*`
/// colors render deterministically regardless of the host scheme.
///
final class DayCellViewSnapshotTests: XCTestCase {

    // MARK: - iPad states

    func test_iPad_today_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "T",
                dayNumber: "6",
                isToday: true,
                isWeekStart: false,
                isWeekend: false,
                isSelected: true,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_today_unselected_showsItalicAndTodayLabel() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "T",
                dayNumber: "6",
                isToday: true,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_weekday_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "W",
                dayNumber: "7",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: true,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_weekday_unselected() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "W",
                dayNumber: "7",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_monday_unselected_tallerTick() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "M",
                dayNumber: "5",
                isToday: false,
                isWeekStart: true,
                isWeekend: false,
                isSelected: false,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_weekend_unselected_shortTickAndDimLetter() {
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "S",
                dayNumber: "10",
                isToday: false,
                isWeekStart: false,
                isWeekend: true,
                isSelected: false,
                distance: 4
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_unselected_farAway_fadedOpacity() {
        // distance 10 → opacity = max(0.22, 1 - 10*0.045) = 0.55
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "F",
                dayNumber: "16",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 10
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPad_unselected_maxDistance_clampedOpacity() {
        // distance 30 → opacity clamped to 0.22
        assertSnapshot(
            of: makeView(
                device: .iPad,
                dayLetter: "F",
                dayNumber: "5",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 30
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    // MARK: - iPhone states

    func test_iPhone_today_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                dayLetter: "T",
                dayNumber: "6",
                isToday: true,
                isWeekStart: false,
                isWeekend: false,
                isSelected: true,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPhone_today_unselected_showsItalic() {
        // iPhone variant has no TODAY label and no baseline marker, but
        // italic + tall tick still apply.
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                dayLetter: "T",
                dayNumber: "6",
                isToday: true,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPhone_weekday_selected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                dayLetter: "W",
                dayNumber: "7",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: true,
                distance: 0
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPhone_weekday_unselected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                dayLetter: "W",
                dayNumber: "7",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 1
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPhone_weekend_unselected() {
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                dayLetter: "S",
                dayNumber: "10",
                isToday: false,
                isWeekStart: false,
                isWeekend: true,
                isSelected: false,
                distance: 4
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    func test_iPhone_unselected_maxDistance_clampedOpacity() {
        // distance 30 → opacity clamped to 0.22 (falloff factor 0.05 on iPhone)
        assertSnapshot(
            of: makeView(
                device: .iPhone,
                dayLetter: "F",
                dayNumber: "5",
                isToday: false,
                isWeekStart: false,
                isWeekend: false,
                isSelected: false,
                distance: 30
            ),
            as: .image(layout: .sizeThatFits)
        )
    }

    // MARK: - Helper

    /// Builds a renderable DayCellView wrapped on the same warm paper background
    /// the wheel sits on in the design, with `colorScheme(.light)` pinned so the
    /// asset catalog resolves to the light variants deterministically.
    private func makeView(
        device: DayCellView.Model.Device,
        dayLetter: String,
        dayNumber: String,
        isToday: Bool,
        isWeekStart: Bool,
        isWeekend: Bool,
        isSelected: Bool,
        distance: Int
    ) -> some View {
        let model = DayCellView.Model(
            device: device,
            dayLetter: dayLetter,
            dayNumber: dayNumber,
            isToday: isToday,
            isWeekStart: isWeekStart,
            isWeekend: isWeekend,
            isSelected: isSelected,
            distanceFromSelection: distance
        )
        return DayCellView(model: model)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(Color("ink/Paper"))
            .colorScheme(.light)
    }
}
