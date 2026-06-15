#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import FromInk

/// CONFIRMATION (2026-06-15): proves the broken-list bug (markers
/// dropping, ordered numbering restarting `1 … 1 2 3 … 1`) is rooted in
/// the NSAttributedString *attribute* representation of block identity —
/// the exact dependency the `ParagraphIndex` authority flip removes.
///
/// `parseBack` derives list structure ENTIRELY from per-paragraph
/// `.blockChrome` / `.groupID` attributes. UIKit's `typingAttributes`
/// strips or desyncs those custom keys on the paragraph created by Enter
/// (documented behaviour the editor fights with re-assert dances). When
/// that preservation fails, the attributes are corrupt and the list
/// fragments — which is exactly the simulator symptom. These tests inject
/// that corruption directly and show the structural fallout.
///
/// If the flip lands (identity in the side-channel index, maintained
/// across Enter, read by parseBack + rendering), none of this can happen
/// — the index is the source of truth and UIKit can't touch it.
@MainActor
final class AttributeCorruptionConfirmationTests: XCTestCase {

    private let bodyFont = UIFont.systemFont(ofSize: 17)
    private let bodyColor = UIColor.label

    /// Baseline: intact attributes → one 3-item ordered list (renders
    /// 1, 2, 3). Establishes that parseBack is correct WHEN the
    /// attributes survive.
    func test_baseline_intactOrderedList_parsesAsSingleList() {
        let flat = TextKitEditorView.flatten(
            document: Self.threeItemOrderedList(), bodyFont: bodyFont, bodyColor: bodyColor
        )
        let recovered = TextKitEditorView.parseBack(flat.attributed)
        XCTAssertEqual(recovered.blocks.count, 1)
        guard case .orderedList(let items) = recovered.blocks[0].kind else {
            return XCTFail("Expected a single ordered list")
        }
        XCTAssertEqual(items.count, 3, "Intact attributes → one 3-item list")
    }

    /// CORRUPTION A — UIKit strips the custom keys from the continuation
    /// paragraphs. parseBack then reads them as plain paragraphs: the
    /// list fragments into [list(one), paragraph, paragraph]. Item 1
    /// keeps its number; the rest lose their marker. This is the
    /// lost-marker symptom.
    func test_corruption_strippedChrome_fragmentsListIntoParagraphs() {
        let flat = TextKitEditorView.flatten(
            document: Self.threeItemOrderedList(), bodyFont: bodyFont, bodyColor: bodyColor
        )
        let mutable = NSMutableAttributedString(attributedString: flat.attributed)
        // Strip identity keys from items 2 and 3 — simulate the
        // typingAttributes custom-key loss on Enter-created lines.
        for range in [flat.flattenMap[1].nsRange, flat.flattenMap[2].nsRange] {
            mutable.removeAttribute(.blockChrome, range: range)
            mutable.removeAttribute(.groupID, range: range)
        }
        let recovered = TextKitEditorView.parseBack(mutable)

        let paragraphCount = recovered.blocks.filter {
            if case .paragraph = $0.kind { return true }; return false
        }.count
        XCTAssertNotEqual(recovered.blocks.count, 1, "Corrupted attributes fragment the single list")
        XCTAssertEqual(paragraphCount, 2, "The two stripped items fall OUT of the list as body paragraphs")
    }

    /// CORRUPTION B — the continuation paragraph keeps list chrome but
    /// gets a DIFFERENT groupID (the desync flavour). parseBack groups
    /// by (groupID + chrome), so a fresh groupID STARTS A NEW LIST →
    /// the numbering restarts at 1. This is the `1 … 1` symptom.
    func test_corruption_desyncedGroupID_restartsNumbering() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "one")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "two")]))])
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let mutable = NSMutableAttributedString(attributedString: flat.attributed)
        // Give item 2 a fresh groupID — what a desynced Enter produces.
        mutable.addAttribute(.groupID, value: UUID(), range: flat.flattenMap[1].nsRange)
        let recovered = TextKitEditorView.parseBack(mutable)

        let lists = recovered.blocks.filter {
            if case .orderedList = $0.kind { return true }; return false
        }
        XCTAssertEqual(lists.count, 2, "A desynced groupID splits one list into two → numbering restarts at 1")
    }

    /// The rendering half: a list paragraph whose `.blockChrome` was
    /// stripped reads back as `nil` at its probe location, so the layout
    /// manager paints NO marker even though the paragraph still carries
    /// the list's indent paragraph style. That mismatch (indented, no
    /// marker) is the other thing visible in the screenshot.
    func test_corruption_strippedChrome_dropsMarkerProbe() {
        let flat = TextKitEditorView.flatten(
            document: Self.threeItemOrderedList(), bodyFont: bodyFont, bodyColor: bodyColor
        )
        let mutable = NSMutableAttributedString(attributedString: flat.attributed)
        let item2 = flat.flattenMap[1].nsRange
        mutable.removeAttribute(.blockChrome, range: item2)

        let chrome = mutable.attribute(.blockChrome, at: item2.location, effectiveRange: nil)
        XCTAssertNil(chrome, "No chrome to probe → drawBackground paints no marker for this line")
        // …yet the indent paragraph style survives, so the line still
        // sits indented — exactly the indented-but-unnumbered rows.
        let style = mutable.attribute(.paragraphStyle, at: item2.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.firstLineHeadIndent, 28, "Indent persists even though the marker is gone")
    }

    // MARK: - Path B: re-stamping from the index heals the corruption

    /// THE FIX, proven: corrupt the storage exactly as UIKit does (strip
    /// chrome + group from continuation items), then re-stamp from the
    /// authoritative index — parseBack recovers the intact single list.
    func test_reStampFromIndex_healsStrippedChrome_listSurvivesParseBack() {
        let doc = Self.threeItemOrderedList()
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let mutable = NSMutableAttributedString(attributedString: flat.attributed)
        for range in [flat.flattenMap[1].nsRange, flat.flattenMap[2].nsRange] {
            mutable.removeAttribute(.blockChrome, range: range)
            mutable.removeAttribute(.groupID, range: range)
        }
        // Sanity: corrupted storage fragments the list (the bug).
        XCTAssertNotEqual(TextKitEditorView.parseBack(mutable).blocks.count, 1)

        // Heal from the authoritative index (what the live wiring will do
        // after structural maintenance).
        let healed = TextKitEditorView.reStampIdentity(on: mutable, from: ParagraphIndex(document: doc))
        XCTAssertTrue(healed)

        let recovered = TextKitEditorView.parseBack(mutable)
        XCTAssertEqual(recovered.blocks.count, 1, "Re-stamp heals the fragmentation")
        guard case .orderedList(let items) = recovered.blocks[0].kind else {
            return XCTFail("Expected a single ordered list after healing")
        }
        XCTAssertEqual(items.count, 3, "All three items back in one list → numbering 1,2,3")
    }

    /// The re-stamp also restores the `.blockChrome` the layout manager
    /// probes, so the markers paint again.
    func test_reStampFromIndex_restoresChromeProbe() {
        let doc = Self.threeItemOrderedList()
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let mutable = NSMutableAttributedString(attributedString: flat.attributed)
        let item2 = flat.flattenMap[1].nsRange
        mutable.removeAttribute(.blockChrome, range: item2)
        XCTAssertNil(mutable.attribute(.blockChrome, at: item2.location, effectiveRange: nil))

        TextKitEditorView.reStampIdentity(on: mutable, from: ParagraphIndex(document: doc))

        let chrome = mutable.attribute(.blockChrome, at: item2.location, effectiveRange: nil) as? Int
        XCTAssertEqual(chrome, BlockChrome.orderedListItem.rawValue, "Marker chrome restored from the index")
    }

    /// Count mismatch (index not yet aligned with the storage) → no-op,
    /// so the caller falls back to the legacy path instead of corrupting.
    func test_reStampFromIndex_countMismatch_isNoOp() {
        let doc = Self.threeItemOrderedList()
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let mutable = NSMutableAttributedString(attributedString: flat.attributed)
        XCTAssertFalse(TextKitEditorView.reStampIdentity(on: mutable, from: ParagraphIndex()))
    }

    private static func threeItemOrderedList() -> RichTextDocument {
        RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "one")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "two")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "three")]))])
            ]))
        ])
    }
}
#endif
