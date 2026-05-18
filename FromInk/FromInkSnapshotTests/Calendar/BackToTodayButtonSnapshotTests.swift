import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `BackToTodayButton` — the small mono "← TODAY"
/// affordance shown beside the masthead while the user is warped.
///
/// The button is purely stateless, so a single rendering per variant is
/// sufficient to lock in the look. We don't snapshot the *pressed* state —
/// that's SwiftUI's own button feedback, not our visual contract.
///
final class BackToTodayButtonSnapshotTests: XCTestCase {

    func test_default() {
        assertSnapshot(
            of: makeView(label: "Today"),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_arabicLabel() {
        // "اليوم" — Arabic for "today". Confirms the mono + uppercase
        // styling falls back gracefully for non-Latin scripts.
        assertSnapshot(
            of: makeView(label: "اليوم", layoutDirection: .rightToLeft),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_verboseFrenchLabel_scalesDown() {
        // "AUJOURD'HUI" is 11 characters — at natural 10pt mono the button
        // grows to ~170pt and crowds the masthead. With minimumScaleFactor
        // 0.7 + allowsTightening, the text shrinks within the pinned 180pt
        // frame. Snapshot locks the visual.
        assertSnapshot(
            of: makeView(label: "Aujourd'hui"),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_russianLabel_scalesDown() {
        // "СЕГОДНЯ" — also wider than English.
        assertSnapshot(
            of: makeView(label: "Сегодня"),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Pinned frame width. `.sizeThatFits` collapses Text inside HStacks
    /// without an explicit width hint. 180pt is comfortable for ← + "TODAY"
    /// with mono tracking.
    private static let viewport: (CGFloat, CGFloat) = (180, 40)

    private func makeView(
        label: String,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> some View {
        HStack {
            BackToTodayButton(label: label, action: { })
            Spacer(minLength: 0)
        }
        .frame(width: Self.viewport.0, height: Self.viewport.1)
        .padding(8)
        .background(Color("ink/Paper"))
        .environment(\.layoutDirection, layoutDirection)
        .colorScheme(.light)
    }
}
