import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `MastheadPill` — the chevron affordance shown
/// beside the masthead date.
///
/// After the iPhone layout pass, the pill no longer carries a text label
/// (was "SCRUB DATES" / a locale-formatted relative date). It is now just
/// a chevron icon rendered larger to read as a clear tap affordance. The
/// only state matrix that matters: closed (chevron down, ink2) vs. open
/// (chevron up via 180° rotation, full ink).
///
final class MastheadPillSnapshotTests: XCTestCase {

    func test_closed_chevronDown() {
        assertSnapshot(
            of: makeView(isExpanded: false),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_open_chevronUp() {
        assertSnapshot(
            of: makeView(isExpanded: true),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    private func makeView(isExpanded: Bool) -> some View {
        MastheadPill(model: .init(isExpanded: isExpanded))
            .frame(width: 40, height: 40)
            .padding(8)
            .background(Color("ink/Paper"))
            .colorScheme(.light)
    }
}
