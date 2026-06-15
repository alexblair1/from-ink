#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import FromInk

/// Pins `ParagraphIndex(document:)`'s construction contract against
/// representative document shapes. Coverage is the shape contract,
/// not behavioral consequences — those land as subsequent commits
/// migrate readers off the attribute-based flatten/parseBack path.
///
/// `@MainActor` is required only for `test_indexRangesMatchFlattenOutput`
/// (which calls `TextKitEditorView.flatten`, MainActor-isolated).
/// `ParagraphIndex(document:)` itself is platform-neutral and runs
/// off-actor.
@MainActor
final class ParagraphIndexTests: XCTestCase {

    // MARK: - Empty / single paragraph

    func test_emptyDocument_emptyIndex() {
        let index = ParagraphIndex(document: .empty)
        XCTAssertTrue(index.entries.isEmpty)
    }

    func test_singleParagraph_singleEntryAtRangeZero() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let doc = RichTextDocument(blocks: [p])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 1)
        let entry = index.entries[0]
        XCTAssertEqual(entry.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(entry.blockPath, [p.id])
        XCTAssertEqual(entry.kind, .paragraph)
        XCTAssertNil(entry.listItemID)
        XCTAssertNil(entry.languageHint)
    }

    func test_emptyParagraph_zeroLengthEntry() {
        let p = Block(kind: .paragraph(inline: []))
        let doc = RichTextDocument(blocks: [p])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 0))
        XCTAssertEqual(index.entries[0].kind, .paragraph)
    }

    // MARK: - Multi-paragraph offset advancement

    func test_twoParagraphs_secondStartsAfterFirstPlusNewline() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World!")]))
        let doc = RichTextDocument(blocks: [p1, p2])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 5))
        // 5 chars + 1 trailing \n = next paragraph starts at 6
        XCTAssertEqual(index.entries[1].range, NSRange(location: 6, length: 6))
        XCTAssertEqual(index.entries[1].blockPath, [p2.id])
    }

    /// Regression guard for Commit 4 (incremental updates): the
    /// "phantom tail" workarounds existed because empty paragraphs
    /// interact badly with attribute-key probing. Pin the offset
    /// advancement through a length-zero entry so the index's
    /// cursor math is correct for the case structural edits will
    /// produce.
    func test_emptyParagraphBetweenNonEmpty_correctOffsetAdvancement() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "A")]))
        let pEmpty = Block(kind: .paragraph(inline: []))
        let p3 = Block(kind: .paragraph(inline: [Inline(text: "B")]))
        let doc = RichTextDocument(blocks: [p1, pEmpty, p3])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 3)
        // "A" at 0..<1
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 1))
        // Empty paragraph at position 2 (after p1's "A" + "\n")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 2, length: 0))
        XCTAssertEqual(index.entries[1].blockPath, [pEmpty.id])
        // "B" at position 3 (after the empty's own trailing "\n")
        XCTAssertEqual(index.entries[2].range, NSRange(location: 3, length: 1))
        XCTAssertEqual(index.entries[2].blockPath, [p3.id])
    }

    // MARK: - Headings

    func test_heading_carriesLevel() {
        let h1 = Block(kind: .heading(level: 1, inline: [Inline(text: "Title")]))
        let h2 = Block(kind: .heading(level: 2, inline: [Inline(text: "Subhead")]))
        let h3 = Block(kind: .heading(level: 3, inline: [Inline(text: "Section")]))
        let doc = RichTextDocument(blocks: [h1, h2, h3])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertEqual(index.entries[0].kind, .heading(level: 1))
        XCTAssertEqual(index.entries[1].kind, .heading(level: 2))
        XCTAssertEqual(index.entries[2].kind, .heading(level: 3))
    }

    // MARK: - Code block

    func test_codeBlock_kindAndLanguageHint() {
        let cb = Block(kind: .codeBlock(text: "let x = 1", languageHint: "swift"))
        let doc = RichTextDocument(blocks: [cb])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 9))
        XCTAssertEqual(index.entries[0].kind, .codeBlock)
        XCTAssertEqual(index.entries[0].languageHint, "swift")
    }

    // MARK: - Divider

    func test_divider_oneCharAnchor() {
        let d = Block(kind: .divider)
        let doc = RichTextDocument(blocks: [d])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 1))
        XCTAssertEqual(index.entries[0].kind, .divider)
    }

    // MARK: - Bulleted list

    func test_bulletList_eachItemIsAnEntryWithListItemID() {
        let item1Paragraph = Block(kind: .paragraph(inline: [Inline(text: "one")]))
        let item2Paragraph = Block(kind: .paragraph(inline: [Inline(text: "two")]))
        let item1 = ListItem(content: [item1Paragraph])
        let item2 = ListItem(content: [item2Paragraph])
        let list = Block(kind: .bulletList(items: [item1, item2]))
        let doc = RichTextDocument(blocks: [list])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 3))
        XCTAssertEqual(index.entries[0].kind, .bulletListItem)
        XCTAssertEqual(index.entries[0].blockPath, [list.id, item1Paragraph.id])
        XCTAssertEqual(index.entries[0].listItemID, item1.id)

        XCTAssertEqual(index.entries[1].range, NSRange(location: 4, length: 3))
        XCTAssertEqual(index.entries[1].kind, .bulletListItem)
        XCTAssertEqual(index.entries[1].blockPath, [list.id, item2Paragraph.id])
        XCTAssertEqual(index.entries[1].listItemID, item2.id)
    }

    // MARK: - Ordered list

    func test_orderedList_distinctKind() {
        let itemParagraph = Block(kind: .paragraph(inline: [Inline(text: "first")]))
        let item = ListItem(content: [itemParagraph])
        let list = Block(kind: .orderedList(items: [item]))
        let doc = RichTextDocument(blocks: [list])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].kind, .orderedListItem)
        XCTAssertEqual(index.entries[0].listItemID, item.id)
    }

    // MARK: - Blockquote

    func test_blockquote_childParagraphHasBlockquoteKindAndContainerPath() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "quoted")]))
        let bq = Block(kind: .blockquote(children: [p]))
        let doc = RichTextDocument(blocks: [bq])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].kind, .blockquoteParagraph)
        XCTAssertEqual(index.entries[0].blockPath, [bq.id, p.id])
    }

    // MARK: - Lookup helpers

    func test_entryForLeafID_findsByLastPathComponent() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "a")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "b")]))
        let doc = RichTextDocument(blocks: [p1, p2])

        let index = ParagraphIndex(document: doc)

        XCTAssertEqual(index.entry(forLeafID: p1.id)?.blockPath, [p1.id])
        XCTAssertEqual(index.entry(forLeafID: p2.id)?.blockPath, [p2.id])
        XCTAssertNil(index.entry(forLeafID: UUID()))
    }

    func test_entryContaining_resolvesCaretWithinParagraph() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        let doc = RichTextDocument(blocks: [p1, p2])

        let index = ParagraphIndex(document: doc)

        // Inside p1
        XCTAssertEqual(index.entry(containing: 0)?.blockPath, [p1.id])
        XCTAssertEqual(index.entry(containing: 3)?.blockPath, [p1.id])
        // End-of-p1 boundary resolves to p1 — matches UIKit's
        // "extend the current paragraph" typingAttributes convention
        XCTAssertEqual(index.entry(containing: 5)?.blockPath, [p1.id])
        // Inside p2 (begins after the \n at position 5)
        XCTAssertEqual(index.entry(containing: 6)?.blockPath, [p2.id])
        XCTAssertEqual(index.entry(containing: 11)?.blockPath, [p2.id])
        // Past the final terminator — phantom tail position; caller
        // is responsible for snapping.
        XCTAssertNil(index.entry(containing: 12))
    }

    // MARK: - Incremental non-structural edits (Commit 4)

    func test_nonStructuralInsert_growsHostShiftsLater() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))

        // Insert "!!" inside p1 at offset 5 (end of "Hello"): no newline.
        index.applyNonStructuralEdit(editedRange: NSRange(location: 5, length: 0), newLength: 2)

        // p1 grows by 2, p2's start shifts by 2 (was 6 → 8).
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 7))
        XCTAssertEqual(index.entries[1].range, NSRange(location: 8, length: 5))
    }

    func test_nonStructuralDelete_shrinksHostShiftsLater() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))

        // Delete "lo" from p1 (offsets 3..<5).
        index.applyNonStructuralEdit(editedRange: NSRange(location: 3, length: 2), newLength: 0)

        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 3))
        XCTAssertEqual(index.entries[1].range, NSRange(location: 4, length: 5))
    }

    func test_nonStructuralEdit_inLastParagraph_noLaterShiftNeeded() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))

        // Insert one char inside p2 (offset 6, start of "World").
        index.applyNonStructuralEdit(editedRange: NSRange(location: 6, length: 0), newLength: 1)

        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 5))
        XCTAssertEqual(index.entries[1].range, NSRange(location: 6, length: 6))
    }

    func test_nonStructuralEdit_intoEmptyParagraph_growsZeroLengthEntry() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "A")]))
        let pEmpty = Block(kind: .paragraph(inline: []))
        let p3 = Block(kind: .paragraph(inline: [Inline(text: "B")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, pEmpty, p3]))

        // Type "x" into the empty paragraph (zero-length range at loc 2).
        index.applyNonStructuralEdit(editedRange: NSRange(location: 2, length: 0), newLength: 1)

        XCTAssertEqual(index.entries[1].range, NSRange(location: 2, length: 1))
        XCTAssertEqual(index.entries[2].range, NSRange(location: 4, length: 1))
    }

    func test_nonStructuralEdit_preservesIdentity() {
        let itemParagraph = Block(kind: .paragraph(inline: [Inline(text: "one")]))
        let item = ListItem(content: [itemParagraph])
        let list = Block(kind: .bulletList(items: [item]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [list]))
        let before = index.entries[0]

        index.applyNonStructuralEdit(editedRange: NSRange(location: 3, length: 0), newLength: 2)

        XCTAssertEqual(index.entries[0].kind, before.kind)
        XCTAssertEqual(index.entries[0].blockPath, before.blockPath)
        XCTAssertEqual(index.entries[0].listItemID, before.listItemID)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 5))
    }

    func test_nonStructuralEdit_zeroDelta_isNoOp() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))
        let before = index.entries

        // Replace one char with one char: delta zero.
        index.applyNonStructuralEdit(editedRange: NSRange(location: 1, length: 1), newLength: 1)

        XCTAssertEqual(index.entries, before)
    }

    func test_nonStructuralEdit_pastLastParagraph_isNoOp() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))
        let before = index.entries

        // Phantom-tail position (past the final \n at location 6).
        index.applyNonStructuralEdit(editedRange: NSRange(location: 7, length: 0), newLength: 1)

        XCTAssertEqual(index.entries, before)
    }

    /// The incremental path must produce EXACTLY what a full rebuild of
    /// the edited document produces — ranges, paths, kinds, identity.
    /// Reusing block IDs across the before/after documents lets us assert
    /// full `Entry` equality, not just range equality.
    func test_nonStructuralEdit_matchesFullRebuild() {
        let p1ID = UUID(), p2ID = UUID(), p3ID = UUID()
        let before = RichTextDocument(blocks: [
            Block(id: p1ID, kind: .paragraph(inline: [Inline(text: "Hello")])),
            Block(id: p2ID, kind: .heading(level: 2, inline: [Inline(text: "Sub")])),
            Block(id: p3ID, kind: .paragraph(inline: [Inline(text: "Tail")]))
        ])
        // Same blocks, but the heading's text edited "Sub" → "Subhead".
        let after = RichTextDocument(blocks: [
            Block(id: p1ID, kind: .paragraph(inline: [Inline(text: "Hello")])),
            Block(id: p2ID, kind: .heading(level: 2, inline: [Inline(text: "Subhead")])),
            Block(id: p3ID, kind: .paragraph(inline: [Inline(text: "Tail")]))
        ])

        var incremental = ParagraphIndex(document: before)
        // "Sub" starts at 6 (after "Hello\n"), ends at 9; append "head".
        incremental.applyNonStructuralEdit(editedRange: NSRange(location: 9, length: 0), newLength: 4)

        XCTAssertEqual(incremental.entries, ParagraphIndex(document: after).entries)
    }

    // MARK: - Range alignment with flatten output

    /// The index's ranges must match what `flatten` actually produces —
    /// they're the same positions both structures address. Regression
    /// guard for divergence as flatten or the builder evolves.
    func test_indexRangesMatchFlattenOutput() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let h2 = Block(kind: .heading(level: 2, inline: [Inline(text: "Subhead")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "Body text")]))
        let doc = RichTextDocument(blocks: [p1, h2, p2])

        let index = ParagraphIndex(document: doc)
        let flattened = TextKitEditorView.flatten(
            document: doc,
            bodyFont: UIFont.systemFont(ofSize: 14),
            bodyColor: .label
        )

        XCTAssertEqual(index.entries.count, flattened.flattenMap.count)
        for (entry, mapEntry) in zip(index.entries, flattened.flattenMap) {
            XCTAssertEqual(entry.range, mapEntry.nsRange)
            XCTAssertEqual(entry.blockPath, mapEntry.blockPath)
        }
    }
}
#endif
