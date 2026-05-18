import XCTest
@testable import FromInk

/// Unit tests for `CenteredCellScrollTargetBehavior.snappedCenterX(...)` —
/// the pure snap math the custom scroll target behavior uses.
///
/// Layout assumed by the math: cells of uniform width laid out without
/// spacing starting at content x=0. Cell N occupies `[N*W, (N+1)*W]`, its
/// center at `N*W + W/2`. The snap rounds the viewport's content-mid-X to
/// the nearest cell center.
///
final class CenteredCellScrollTargetBehaviorTests: XCTestCase {

    typealias Behavior = CenteredCellScrollTargetBehavior

    // MARK: - Exact cell centers

    func test_atCellCenter_snapsToSameCell() {
        // Cell 0 center = 28 (for cellWidth 56) — should stay put.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 28, cellWidth: 56), 28)
        // Cell 5 center = 5*56 + 28 = 308.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 308, cellWidth: 56), 308)
    }

    // MARK: - Between cells — rounds to nearest

    func test_slightlyLeftOfCell_snapsToThatCell() {
        // 26 is 2pt left of cell 0 center (28). Nearest cell is 0.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 26, cellWidth: 56), 28)
    }

    func test_slightlyRightOfCell_snapsToThatCell() {
        // 30 is 2pt right of cell 0 center. Nearest cell is 0.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 30, cellWidth: 56), 28)
    }

    func test_pastCellBoundary_snapsToNextCell() {
        // 60 is past cell 0's right edge (56). Nearest center is cell 1's (84).
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 60, cellWidth: 56), 84)
    }

    // MARK: - Halfway between cell centers

    func test_exactlyHalfwayBetweenCells_landsOnOneOrTheOther() {
        // Cell 0 center = 28, cell 1 center = 84. Halfway = 56 (cell 0/1 boundary).
        // Swift's .rounded() defaults to .toNearestOrAwayFromZero. For positive
        // halves it rounds up, so 56 should snap to cell 1's center (84).
        // Either way is acceptable as long as the result is one of {28, 84}.
        let result = Behavior.snappedCenterX(forContentMidX: 56, cellWidth: 56)
        XCTAssert(result == 28 || result == 84, "halfway must land on a cell center, got \(result)")
    }

    // MARK: - iPhone cell width

    func test_snapWorksForIPhoneCellWidth() {
        // iPhone cells are 44pt wide. Cell N center = N*44 + 22.
        // Cell 3 center = 3*44 + 22 = 154.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 154, cellWidth: 44), 154)
        // Just past cell 3 → cell 4 center at 198.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 180, cellWidth: 44), 198, accuracy: 0.001)
    }

    // MARK: - Negative (overscroll past the leading edge)

    func test_negativeMidX_returnsNegativeCellCenter() {
        // Overscrolled past content origin — math still returns a snap target
        // (which the ScrollView's bounds will clamp on actually settling).
        // -28 is "cell -1's center" (-1*56 + 28 = -28).
        let result = Behavior.snappedCenterX(forContentMidX: -10, cellWidth: 56)
        XCTAssertEqual(result, -28)
    }

    // MARK: - Many cells

    func test_atFarRightCellCenter_snapsCorrectly() {
        // Cell 90 center for 56pt cells = 90*56 + 28 = 5068.
        XCTAssertEqual(Behavior.snappedCenterX(forContentMidX: 5068, cellWidth: 56), 5068)
    }
}
