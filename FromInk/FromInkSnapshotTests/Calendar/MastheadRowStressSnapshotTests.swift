import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Stress tests for the masthead row — `MastheadDateBlock + MastheadPill +
/// BackToTodayButton` laid out together as they are in `HomeDailyBrief`.
///
/// Verifies the layout-pressure cascade holds up under realistic worst-case
/// localizations:
///
/// 1. **`Spacer()`** between masthead and button collapses to 0pt.
/// 2. **`BackToTodayButton`** (`.layoutPriority(-1)`) yields first — its
///    text scales via `.minimumScaleFactor(0.7)` and tightens kerning.
/// 3. **`MastheadDateBlock`** (default priority) scales next — compact
///    `.minimumScaleFactor(0.5)` is the final floor.
///
/// This is the only place where we snapshot a *composite* layout that
/// mirrors a feature view. Reason: the individual component snapshots
/// can't catch layout-priority bugs; only the assembled HStack can.
///
final class MastheadRowStressSnapshotTests: XCTestCase {

    // MARK: - Viewport widths

    /// iPhone 17 width minus standard horizontal padding (12pt × 2 = 24pt).
    private static let iPhone17Inner: CGFloat = 393 - 24

    /// iPhone SE / first-gen mini width minus standard horizontal padding.
    /// The narrowest device we care about.
    private static let iPhoneSEInner: CGFloat = 320 - 24

    /// iPad regular split-view minimum width.
    private static let iPadRegularInner: CGFloat = 700

    // MARK: - Baseline (en_US)

    func test_baseline_english_iPhone() {
        assertSnapshot(
            of: makeRow(
                weekday: "Thursday",
                monthDay: "May 14",
                todayLabel: "Today",
                isWarped: true,
                viewportWidth: Self.iPhone17Inner,
                compact: true
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Verbose Latin + Cyrillic stress

    func test_verbose_german_plus_russian_iPhone17() {
        // "Mittwoch" (8ch, no comma) + "14. Mai" + "Сегодня" (Russian Today)
        assertSnapshot(
            of: makeRow(
                weekday: "Mittwoch",
                monthDay: "14. Mai",
                todayLabel: "Сегодня",
                isWarped: true,
                viewportWidth: Self.iPhone17Inner,
                compact: true
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_verbose_german_plus_russian_iPhoneSE_extreme() {
        // Same content, narrower viewport — forces the cascade past the
        // back-to-today button's 0.7 scale floor and into the masthead's
        // 0.5 floor.
        assertSnapshot(
            of: makeRow(
                weekday: "Mittwoch",
                monthDay: "14. Mai",
                todayLabel: "Сегодня",
                isWarped: true,
                viewportWidth: Self.iPhoneSEInner,
                compact: true
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - French (longest "Today" translation)

    func test_french_aujourdhui_iPhone17() {
        assertSnapshot(
            of: makeRow(
                weekday: "Mercredi",
                monthDay: "14 mai",
                todayLabel: "Aujourd'hui",
                isWarped: true,
                viewportWidth: Self.iPhone17Inner,
                compact: true
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - RTL stress

    func test_arabic_rtl_iPhone17() {
        // "الأربعاء" Wednesday + "١٤ مايو" + "اليوم" Today
        assertSnapshot(
            of: makeRow(
                weekday: "الأربعاء",
                monthDay: "١٤ مايو",
                todayLabel: "اليوم",
                isWarped: true,
                viewportWidth: Self.iPhone17Inner,
                compact: true,
                layoutDirection: .rightToLeft
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Regular width (iPad) — verify no scaling occurs at this size

    func test_verbose_iPad_regular_noScaling() {
        // German + Russian on iPad regular width — should render at natural
        // size with plenty of breathing room. No minimumScaleFactor trigger.
        assertSnapshot(
            of: makeRow(
                weekday: "Mittwoch",
                monthDay: "14. Mai",
                todayLabel: "Сегодня",
                isWarped: true,
                viewportWidth: Self.iPadRegularInner,
                compact: false
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Not warped (back-to-today hidden)

    func test_notWarped_iPhone17_noBackButton() {
        assertSnapshot(
            of: makeRow(
                weekday: "Thursday",
                monthDay: "May 14",
                todayLabel: "Today",  // unused since isWarped=false
                isWarped: false,
                viewportWidth: Self.iPhone17Inner,
                compact: true
            ),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Helper

    /// Constructs an HStack that mirrors `HomeDailyBrief`'s masthead row:
    /// the masthead button (date + chevron pill) on the leading side,
    /// a Spacer, and the optional ← TODAY button on the trailing side.
    private func makeRow(
        weekday: String,
        monthDay: String,
        todayLabel: String,
        isWarped: Bool,
        viewportWidth: CGFloat,
        compact: Bool,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Mimic the masthead button: date + chevron pill in an HStack
            // wrapped in a Button. We render the inner content only since
            // the visual is the same.
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                MastheadDateBlock(model: .init(
                    weekday: weekday,
                    monthDay: monthDay,
                    compact: compact
                ))
                MastheadPill(model: .init(isExpanded: false))
                    .padding(.bottom, 4)
            }

            Spacer(minLength: 0)

            if isWarped {
                BackToTodayButton(label: todayLabel, action: { })
            }
        }
        .frame(width: viewportWidth, alignment: .leading)
        .padding(.vertical, 12)
        .background(Color("ink/Paper"))
        .environment(\.layoutDirection, layoutDirection)
        .colorScheme(.light)
    }
}
