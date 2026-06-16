import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `AccessoryBarView` — the iPhone / iPad-compact
/// keyboard accessory bar (EDD §14.4.1), default mode. Bold shown active.
final class AccessoryBarViewSnapshotTests: XCTestCase {

    func test_accessoryBar_defaultMode_boldActive() {
        let leading: [AccessoryBarView.Button] = [
            .init(id: "aa", content: .text("Aa"), accessibilityLabel: AppStrings.AccessoryBar.formatStyle, onTap: {}),
            .init(id: "bold", content: .symbol("bold"), accessibilityLabel: AppStrings.AccessoryBar.bold,
                  isActive: true, onTap: {}),
            .init(id: "italic", content: .symbol("italic"), accessibilityLabel: AppStrings.AccessoryBar.italic, onTap: {}),
            .init(id: "underline", content: .symbol("underline"),
                  accessibilityLabel: AppStrings.AccessoryBar.underline, onTap: {}),
            .init(id: "bulleted", content: .symbol("list.bullet"),
                  accessibilityLabel: AppStrings.AccessoryBar.bulletedList, onTap: {}),
            .init(id: "numbered", content: .symbol("list.number"),
                  accessibilityLabel: AppStrings.AccessoryBar.numberedList, onTap: {})
        ]
        let trailing: [AccessoryBarView.Button] = [
            .init(id: "undo", content: .symbol("arrow.uturn.backward"),
                  accessibilityLabel: AppStrings.AccessoryBar.undo, onTap: {}),
            .init(id: "dismiss", content: .symbol("keyboard.chevron.compact.down"),
                  accessibilityLabel: AppStrings.AccessoryBar.dismissKeyboard, onTap: {})
        ]
        let view = AccessoryBarView(model: .init(buttons: leading, trailingButtons: trailing))
            .frame(width: 390)

        assertSnapshot(of: view, as: .image(layout: .sizeThatFits), record: false)
    }
}
