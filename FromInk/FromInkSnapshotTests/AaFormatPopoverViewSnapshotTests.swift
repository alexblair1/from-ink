import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `AaFormatPopoverView` — the iPhone /
/// iPad-compact "Aa" formatting popover (EDD §14.4.2). Stateless
/// component, rendered from a flat Model with representative state:
/// Body active in the block section, Bold active inline, Checklist
/// shown as coming-soon.
final class AaFormatPopoverViewSnapshotTests: XCTestCase {

    func test_aaPopover_defaultState() {
        assertSnapshot(
            of: makeView(activeBlockID: "body", activeInlineIDs: ["bold"]),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    func test_aaPopover_headingActive() {
        assertSnapshot(
            of: makeView(activeBlockID: "title", activeInlineIDs: []),
            as: .image(layout: .sizeThatFits),
            record: false
        )
    }

    // MARK: - Fixtures

    private func makeView(activeBlockID: String, activeInlineIDs: Set<String>) -> some View {
        let blockRows: [AaFormatPopoverView.Row] = [
            .init(id: "title", icon: "textformat.size.larger", title: AppStrings.AccessoryBar.title,
                  isActive: activeBlockID == "title", onTap: {}),
            .init(id: "heading", icon: "textformat.size", title: AppStrings.AccessoryBar.heading,
                  isActive: activeBlockID == "heading", onTap: {}),
            .init(id: "subheading", icon: "textformat.size.smaller", title: AppStrings.AccessoryBar.subheading,
                  isActive: activeBlockID == "subheading", onTap: {}),
            .init(id: "body", icon: "text.alignleft", title: AppStrings.AccessoryBar.body,
                  isActive: activeBlockID == "body", onTap: {}),
            .init(id: "code", icon: "curlybraces", title: AppStrings.AccessoryBar.code,
                  isActive: activeBlockID == "code", onTap: {}),
            .init(id: "quote", icon: "quote.opening", title: AppStrings.AccessoryBar.blockQuote,
                  isActive: activeBlockID == "quote", onTap: {})
        ]
        let inlineToggles: [AaFormatPopoverView.InlineToggle] = [
            .init(id: "bold", icon: "bold", accessibilityLabel: AppStrings.AccessoryBar.bold,
                  isActive: activeInlineIDs.contains("bold"), onTap: {}),
            .init(id: "italic", icon: "italic", accessibilityLabel: AppStrings.AccessoryBar.italic,
                  isActive: activeInlineIDs.contains("italic"), onTap: {}),
            .init(id: "underline", icon: "underline", accessibilityLabel: AppStrings.AccessoryBar.underline,
                  isActive: activeInlineIDs.contains("underline"), onTap: {}),
            .init(id: "strikethrough", icon: "strikethrough",
                  accessibilityLabel: AppStrings.AccessoryBar.strikethrough,
                  isActive: activeInlineIDs.contains("strikethrough"), onTap: {})
        ]
        let listRows: [AaFormatPopoverView.Row] = [
            .init(id: "bulleted", icon: "list.bullet", title: AppStrings.AccessoryBar.bulletedList, onTap: {}),
            .init(id: "numbered", icon: "list.number", title: AppStrings.AccessoryBar.numberedList, onTap: {}),
            .init(id: "checklist", icon: "checklist", title: AppStrings.AccessoryBar.checklist,
                  isComingSoon: true, onTap: {})
        ]
        return AaFormatPopoverView(model: .init(
            blockRows: blockRows,
            inlineToggles: inlineToggles,
            listRows: listRows
        ))
        .padding(40)
        .background(Color(white: 0.92))
    }
}
