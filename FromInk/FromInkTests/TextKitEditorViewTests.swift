#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import FromInk

/// Pins the `TextKitEditorView`'s flatten / parse-back contract.
///
/// The editor's load-bearing claims:
///
///   - Flatten produces one paragraph per leaf block, joined by `\n`.
///   - Each paragraph carries `.blockChrome`, `.blockID`, and (where
///     applicable) `.groupID` attributes so the layout manager can
///     paint chrome and the parse-back can re-group containers.
///   - Parse-back reconstructs a structurally-equivalent
///     `RichTextDocument`. Block IDs are preserved verbatim where the
///     `.blockID` attribute survives the round-trip; new paragraphs
///     (e.g. from Enter) get fresh UUIDs.
///   - The flatten map exposes per-paragraph `NSRange` ↔ block-path
///     correspondences used by the selection bridge.
///
/// Both directions are tested end-to-end so structural regressions
/// surface before they hit the UI.
@MainActor
final class TextKitEditorViewTests: XCTestCase {

    private let bodyFont = UIFont.systemFont(ofSize: 17)
    private let bodyColor = UIColor.label

    // MARK: - Flatten — produces expected attributes per paragraph

    func test_flatten_paragraph_emitsBlockChromeAndBlockID() {
        let id = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id, kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(result.attributed.string, "Hello")
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.blockChrome] as? Int, BlockChrome.paragraph.rawValue)
        XCTAssertEqual(attrs[.blockID] as? UUID, id)
        XCTAssertNil(attrs[.groupID], "Top-level paragraph has no group id")
    }

    func test_flatten_heading_emitsCorrectChrome() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 2, inline: [Inline(text: "Title")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.blockChrome] as? Int, BlockChrome.heading2.rawValue)
    }

    func test_flatten_bulletList_emitsSharedGroupID() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "A")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "B")]))])
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(result.attributed.string, "A\nB")

        let firstAttrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        // Index 2 is the start of "B" (after "A\n").
        let secondAttrs = result.attributed.attributes(at: 2, effectiveRange: nil)
        XCTAssertEqual(firstAttrs[.blockChrome] as? Int, BlockChrome.bulletListItem.rawValue)
        XCTAssertEqual(secondAttrs[.blockChrome] as? Int, BlockChrome.bulletListItem.rawValue)
        XCTAssertEqual(
            firstAttrs[.groupID] as? UUID,
            secondAttrs[.groupID] as? UUID,
            "Both bullet items must share the same groupID"
        )
    }

    func test_flatten_orderedList_emitsSharedGroupID() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "1st")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "2nd")]))])
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let firstAttrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        let secondAttrs = result.attributed.attributes(at: 4, effectiveRange: nil)
        XCTAssertEqual(firstAttrs[.blockChrome] as? Int, BlockChrome.orderedListItem.rawValue)
        XCTAssertEqual(secondAttrs[.blockChrome] as? Int, BlockChrome.orderedListItem.rawValue)
        XCTAssertEqual(firstAttrs[.groupID] as? UUID, secondAttrs[.groupID] as? UUID)
    }

    func test_flatten_blockquote_emitsSharedGroupID() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quote")]))
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.blockChrome] as? Int, BlockChrome.paragraph.rawValue,
                       "Inner block keeps its own chrome (paragraph) — blockquote container info lives in groupID")
        XCTAssertNotNil(attrs[.groupID])
    }

    func test_flatten_divider_emitsDividerChromeAndAnchorChar() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .divider)
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(result.attributed.string, "\u{00A0}")
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.blockChrome] as? Int, BlockChrome.divider.rawValue)
    }

    // MARK: - Parse-back — reconstructs structure

    func test_parseBack_simpleParagraph_roundTrips() {
        let id = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id, kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        XCTAssertEqual(recovered.blocks.count, 1)
        guard case .paragraph(let inline) = recovered.blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        XCTAssertEqual(inline.first?.text, "Hello")
        XCTAssertEqual(recovered.blocks[0].id, id, "Block id preserved through flatten/parse-back")
    }

    func test_parseBack_heading_recoversLevel() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 3, inline: [Inline(text: "H3")]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        guard case .heading(let level, let inline) = recovered.blocks[0].kind else {
            XCTFail("Expected heading")
            return
        }
        XCTAssertEqual(level, 3)
        XCTAssertEqual(inline.first?.text, "H3")
    }

    func test_parseBack_bulletList_regroupsContainers() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "A")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "B")]))])
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        XCTAssertEqual(recovered.blocks.count, 1, "Two bullet items must re-group into one bulletList container")
        guard case .bulletList(let items) = recovered.blocks[0].kind else {
            XCTFail("Expected bulletList")
            return
        }
        XCTAssertEqual(items.count, 2)
    }

    func test_parseBack_orderedList_regroupsContainers() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "1st")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "2nd")]))])
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        guard case .orderedList(let items) = recovered.blocks[0].kind else {
            XCTFail("Expected orderedList")
            return
        }
        XCTAssertEqual(items.count, 2)
    }

    func test_parseBack_codeBlock_emitsCodeBlock() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .codeBlock(text: "let x = 1", languageHint: nil))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        guard case .codeBlock(let text, _) = recovered.blocks[0].kind else {
            XCTFail("Expected codeBlock")
            return
        }
        XCTAssertEqual(text, "let x = 1")
    }

    func test_parseBack_divider_emitsDivider() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .divider)
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        // Note: parse-back currently builds the divider as
        // `Block(kind: .divider)`; the leading "\u{00A0}" anchor is
        // recovered as the divider block.
        if case .divider = recovered.blocks[0].kind {
            // ok
        } else {
            XCTFail("Expected divider")
        }
    }

    // MARK: - Inline marks (bold + italic) — recoverable from font traits

    func test_parseBack_boldInline_recoveredFromFontTraits() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "Plain "),
                Inline(text: "bold", marks: [.bold])
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
        guard case .paragraph(let inline) = recovered.blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        // First run plain, second run bold.
        XCTAssertEqual(inline.count, 2)
        XCTAssertEqual(inline[0].text, "Plain ")
        XCTAssertEqual(inline[0].marks, [])
        XCTAssertEqual(inline[1].text, "bold")
        XCTAssertEqual(inline[1].marks, [.bold])
    }

    // MARK: - Selection bridge

    func test_nsRange_forSelection_findsCorrectParagraph() {
        let id1 = UUID()
        let id2 = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id1, kind: .paragraph(inline: [Inline(text: "First")])),
            Block(id: id2, kind: .paragraph(inline: [Inline(text: "Second")]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let selection = BlockTreeSelection(path: [id2], startUTF16: 0, endUTF16: 6)
        let nsRange = TextKitEditorView.nsRange(
            for: selection,
            flattenMap: flattened.flattenMap,
            totalLength: flattened.attributed.length
        )
        XCTAssertNotNil(nsRange)
        XCTAssertEqual(nsRange?.location, 6, "After 'First\\n' the second paragraph starts at offset 6")
        XCTAssertEqual(nsRange?.length, 6)
    }

    func test_selection_forNSRange_findsCorrectPath() {
        let id1 = UUID()
        let id2 = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id1, kind: .paragraph(inline: [Inline(text: "First")])),
            Block(id: id2, kind: .paragraph(inline: [Inline(text: "Second")]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Range at offset 8 (inside "Second" — "Se|cond"), length 0
        let nsRange = NSRange(location: 8, length: 0)
        let bridged = TextKitEditorView.selection(
            forNSRange: nsRange,
            flattenMap: flattened.flattenMap
        )
        XCTAssertEqual(bridged.path, [id2])
        XCTAssertEqual(bridged.startUTF16, 2)
        XCTAssertEqual(bridged.endUTF16, 2)
    }
}
#endif
