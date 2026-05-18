import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `MastheadPill` — the chevron + label affordance
/// shown beside the masthead date.
///
/// The state matrix that matters visually:
/// - Closed (wheel not open) → chevron down, color quieted (ink2)
/// - Open (wheel open) → chevron rotated 180°, color full ink
/// - Warped + closed → same chevron orientation, different text (e.g.
///   `"3 days ago"`) — verified via a fixed relative-date string here
///   rather than RelativeDateTimeFormatter (whose output is locale data,
///   not our visual contract).
///
/// Locale stress tests confirm the mono + uppercase styling holds for
/// non-Latin scripts where `.textCase(.uppercase)` is a no-op.
///
final class MastheadPillSnapshotTests: XCTestCase {

    func test_closed_scrubDates() {
        assertSnapshot(
            of: makeView(text: "Scrub dates", isExpanded: false),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_open_scrubDates() {
        assertSnapshot(
            of: makeView(text: "Scrub dates", isExpanded: true),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_closed_warpedRelativeLabel() {
        assertSnapshot(
            of: makeView(text: "3 days ago", isExpanded: false),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_closed_warpedFuture() {
        assertSnapshot(
            of: makeView(text: "in 1 week", isExpanded: false),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_arabic_open_scrubDates() {
        // ar_SA "تقليب التواريخ" — locale-aware label rendering, RTL layout.
        assertSnapshot(
            of: makeView(
                text: "تقليب التواريخ",
                isExpanded: true,
                layoutDirection: .rightToLeft
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_japanese_closed_warpedLabel() {
        // ja_JP "3日前" — locale digits + ideograph; tests the mono
        // monospaced design substitution behavior.
        assertSnapshot(
            of: makeView(text: "3日前", isExpanded: false),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    /// Pinned frame width. `.sizeThatFits` collapses Text views inside
    /// HStacks in the snapshot host when no frame is pinned — the layout
    /// engine doesn't have a parent to reference for available width. 240pt
    /// is wide enough for the longest expected label ("SCRUB DATES" with
    /// tracking + chevron) with plenty of slack.
    private static let viewport: (CGFloat, CGFloat) = (240, 32)

    private func makeView(
        text: String,
        isExpanded: Bool,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> some View {
        HStack {
            MastheadPill(model: .init(text: text, isExpanded: isExpanded))
            Spacer(minLength: 0)
        }
        .frame(width: Self.viewport.0, height: Self.viewport.1)
        .padding(8)
        .background(Color("ink/Paper"))
        .environment(\.layoutDirection, layoutDirection)
        .colorScheme(.light)
    }
}
