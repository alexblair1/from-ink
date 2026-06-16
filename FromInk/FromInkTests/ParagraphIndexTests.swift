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

    // MARK: - Structural split (Enter)

    func test_split_paragraphInMiddle_makesTwoParagraphs() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "HelloWorld")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1]))

        index.applyStructuralSplit(at: 5)  // after "Hello"

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 5))
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "First half keeps the original identity")
        XCTAssertEqual(index.entries[0].kind, .paragraph)
        XCTAssertEqual(index.entries[1].range, NSRange(location: 6, length: 5), "Second half begins after the new \\n")
        XCTAssertEqual(index.entries[1].kind, .paragraph)
        XCTAssertNotEqual(index.entries[1].blockPath, [p1.id], "Second half gets a fresh id")
    }

    func test_split_listItemAtEnd_makesNewItemInSameContainer() {
        let itemPara = Block(kind: .paragraph(inline: [Inline(text: "one")]))
        let item = ListItem(content: [itemPara])
        let list = Block(kind: .bulletList(items: [item]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [list]))

        index.applyStructuralSplit(at: 3)  // Enter at end of "one"

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 3))
        XCTAssertEqual(index.entries[0].kind, .bulletListItem)
        XCTAssertEqual(index.entries[1].range, NSRange(location: 4, length: 0), "New empty item after the \\n")
        XCTAssertEqual(index.entries[1].kind, .bulletListItem, "Stays a list item — this is what UIKit corrupts")
        XCTAssertEqual(index.entries[1].blockPath.first, list.id, "Same list container → numbering continues")
        XCTAssertNotEqual(index.entries[1].blockPath.last, itemPara.id, "Fresh leaf id")
        XCTAssertNotNil(index.entries[1].listItemID)
        XCTAssertNotEqual(index.entries[1].listItemID, item.id, "Fresh listItemID")
    }

    func test_split_heading_demotesSecondHalfToParagraph() {
        let h = Block(kind: .heading(level: 2, inline: [Inline(text: "Title")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [h]))

        index.applyStructuralSplit(at: 5)

        XCTAssertEqual(index.entries[0].kind, .heading(level: 2))
        XCTAssertEqual(index.entries[1].kind, .paragraph, "Enter after a heading drops to body")
    }

    func test_split_blockquoteParagraph_keepsContainer() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "quote")]))
        let bq = Block(kind: .blockquote(children: [p]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [bq]))

        index.applyStructuralSplit(at: 5)

        XCTAssertEqual(index.entries[1].kind, .blockquoteParagraph)
        XCTAssertEqual(index.entries[1].blockPath.first, bq.id, "Same blockquote container")
    }

    func test_split_shiftsLaterParagraphs() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "AB")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "CD")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))

        index.applyStructuralSplit(at: 1)  // split "AB" → "A" / "B"

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 1))
        XCTAssertEqual(index.entries[1].range, NSRange(location: 2, length: 1))
        XCTAssertEqual(index.entries[2].range, NSRange(location: 4, length: 2), "p2 shifts by the inserted \\n")
        XCTAssertEqual(index.entries[2].blockPath, [p2.id], "p2 identity unchanged")
    }

    func test_split_atParagraphStart_leavesEmptyFirstHalf() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))

        index.applyStructuralSplit(at: 0)

        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 0), "Empty first half")
        XCTAssertEqual(index.entries[0].blockPath, [p.id], "Original keeps identity")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 1, length: 5), "Content moves to the second half")
    }

    func test_split_outsideAnyParagraph_isNoOp() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "Hi")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))
        let before = index.entries

        index.applyStructuralSplit(at: 99)

        XCTAssertEqual(index.entries, before)
    }

    // MARK: - Structural split with replacingLength (selection + Enter)

    /// Selection + Enter in a single paragraph: the selected chars are
    /// deleted and replaced by a `\n`. First half keeps the original
    /// paragraph's identity; second half is a fresh body paragraph
    /// holding the unselected trailing text.
    func test_split_replacingMidSelection_dropsSelectedChars() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "ABCxxxDEF")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))
        // Select "xxx" at positions [3, 3) and press Enter.
        index.applyStructuralSplit(at: 3, replacingLength: 3)

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 3), "First half: 'ABC'")
        XCTAssertEqual(index.entries[0].blockPath, [p.id], "Original keeps its identity")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 4, length: 3), "Second half: 'DEF'")
        XCTAssertNotEqual(index.entries[1].blockPath, [p.id], "Second half gets a fresh id")
    }

    /// Selection + Enter still shifts later paragraphs by the net delta
    /// (`+1` for the inserted `\n` minus the selection's length).
    func test_split_replacing_shiftsLaterParagraphs() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "ABCxxxDEF")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "GHI")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))
        // Pre-edit: p1(0,9) p2(10,3). Selection [3, 3) replaced by `\n`
        // → "ABC\nDEF\nGHI": p1.first(0,3) p1.second(4,3) p2(8,3).
        // Later-shift = 1 - 3 = -2.
        index.applyStructuralSplit(at: 3, replacingLength: 3)

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 3))
        XCTAssertEqual(index.entries[1].range, NSRange(location: 4, length: 3))
        XCTAssertEqual(index.entries[2].range, NSRange(location: 8, length: 3))
        XCTAssertEqual(index.entries[2].blockPath, [p2.id], "p2 identity unchanged")
    }

    /// Selection + Enter inside a list item: both halves are list items
    /// in the same container (matching pure-Enter list-item split).
    func test_split_replacing_listItem_secondHalfNewListItem() {
        let para = Block(kind: .paragraph(inline: [Inline(text: "ABCxxxDEF")]))
        let item = ListItem(content: [para])
        let list = Block(kind: .bulletList(items: [item]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [list]))

        index.applyStructuralSplit(at: 3, replacingLength: 3)

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].kind, .bulletListItem)
        XCTAssertEqual(index.entries[1].kind, .bulletListItem, "Selection+Enter inside a list adds a new list item")
        XCTAssertEqual(index.entries[0].blockPath.first, list.id)
        XCTAssertEqual(index.entries[1].blockPath.first, list.id, "New item lives in the same list container")
        XCTAssertNotEqual(index.entries[1].listItemID, index.entries[0].listItemID, "Fresh ListItem id")
    }

    /// Selecting the entire paragraph and pressing Enter leaves an
    /// empty first half (the original) and an empty second half (the
    /// fresh paragraph).
    func test_split_replacing_entireParagraph_leavesTwoEmptyEntries() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "ABC")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))

        index.applyStructuralSplit(at: 0, replacingLength: 3)

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 0))
        XCTAssertEqual(index.entries[1].range, NSRange(location: 1, length: 0))
    }

    /// Defensive: a `replacingLength` larger than the host paragraph's
    /// remaining text leaves the index unchanged. The caller is
    /// expected to have clamped the selection to one paragraph before
    /// dispatching the split, so this guard is a backstop.
    func test_split_replacing_overrun_isNoOp() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "ABC")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))
        let before = index.entries

        index.applyStructuralSplit(at: 1, replacingLength: 99)

        XCTAssertEqual(index.entries, before)
    }

    // MARK: - Structural merge (backspace join)

    func test_merge_twoParagraphs_predecessorAbsorbsAndKeepsIdentity() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "AB")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "CD")]))
        let p3 = Block(kind: .paragraph(inline: [Inline(text: "EF")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2, p3]))
        // "AB\nCD\nEF\n": p1(0,2) p2(3,2) p3(6,2). Backspace at start of p2 (3).
        index.applyStructuralMerge(atParagraphStart: 3)

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 4), "p1 absorbs p2's text")
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "Predecessor keeps its identity")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 5, length: 2), "p3 shifts back by the deleted \\n")
        XCTAssertEqual(index.entries[1].blockPath, [p3.id])
    }

    func test_merge_bodyIntoListItem_staysListItem() {
        let itemPara = Block(kind: .paragraph(inline: [Inline(text: "one")]))
        let item = ListItem(content: [itemPara])
        let list = Block(kind: .bulletList(items: [item]))
        let body = Block(kind: .paragraph(inline: [Inline(text: "two")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [list, body]))
        // "one\ntwo\n": item(0,3) body(4,3). Backspace at start of body (4).
        index.applyStructuralMerge(atParagraphStart: 4)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].kind, .bulletListItem, "Merged result keeps the list item's kind")
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 6))
        XCTAssertEqual(index.entries[0].blockPath.first, list.id)
    }

    func test_merge_emptyParagraphUp_absorbsNothing() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "AB")]))
        let pEmpty = Block(kind: .paragraph(inline: []))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, pEmpty]))
        // "AB\n\n": p1(0,2) pEmpty(3,0). Backspace at start of the empty (3).
        index.applyStructuralMerge(atParagraphStart: 3)

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 2))
        XCTAssertEqual(index.entries[0].blockPath, [p1.id])
    }

    func test_merge_atFirstParagraph_isNoOp() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "AB")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "CD")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))
        let before = index.entries

        index.applyStructuralMerge(atParagraphStart: 0)  // nothing to merge into

        XCTAssertEqual(index.entries, before)
    }

    func test_merge_atNonParagraphStart_isNoOp() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "AB")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "CD")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))
        let before = index.entries

        index.applyStructuralMerge(atParagraphStart: 1)  // mid-paragraph, not a start

        XCTAssertEqual(index.entries, before)
    }

    /// Split then merge at the same point round-trips the ranges (the
    /// fresh ids differ, but the structure/positions return to start).
    func test_splitThenMerge_restoresRangesAndCount() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "HelloWorld")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1]))

        index.applyStructuralSplit(at: 5)        // → "Hello" / "World"
        index.applyStructuralMerge(atParagraphStart: 6)  // join "World" back up

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 10))
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "Predecessor (original) identity survives the round trip")
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

    // MARK: - applyEdit (the generalized structural-edit handler)

    /// Pure within-paragraph edit: applyEdit matches applyNonStructuralEdit.
    func test_applyEdit_pureNonStructural_growsHostShiftsLater() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))

        index.applyEdit(replacing: NSRange(location: 5, length: 0), with: "!!")

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 7))
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "Host keeps identity")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 8, length: 5), "p2 shifts by +2")
    }

    /// Multi-line paste at caret mid-paragraph — host keeps identity,
    /// extra paragraphs are fresh top-level body.
    func test_applyEdit_multiLinePaste_atCaret_splitsIntoThree() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1]))

        index.applyEdit(replacing: NSRange(location: 5, length: 0), with: "ab\ncd\nef")

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 7), "Helloab")
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "First entry keeps identity")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 8, length: 2), "cd")
        XCTAssertNotEqual(index.entries[1].blockPath, [p1.id], "Middle entry is fresh")
        XCTAssertEqual(index.entries[2].range, NSRange(location: 11, length: 8), "ef + ' World'")
        XCTAssertNotEqual(index.entries[2].blockPath, [p1.id], "Last entry is fresh")
    }

    /// Multi-line paste into a bullet list item: extra lines become
    /// new bullet items in the same container.
    func test_applyEdit_multiLinePaste_intoBulletList_makesNewItems() {
        let para = Block(kind: .paragraph(inline: [Inline(text: "row")]))
        let item = ListItem(content: [para])
        let list = Block(kind: .bulletList(items: [item]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [list]))

        index.applyEdit(replacing: NSRange(location: 3, length: 0), with: "A\nB")

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertEqual(index.entries[0].kind, .bulletListItem)
        XCTAssertEqual(index.entries[1].kind, .bulletListItem, "Middle is a new bullet item")
        XCTAssertEqual(index.entries[2].kind, .bulletListItem, "Last is a new bullet item")
        XCTAssertEqual(index.entries[0].blockPath.first, list.id)
        XCTAssertEqual(index.entries[1].blockPath.first, list.id, "Same container")
        XCTAssertEqual(index.entries[2].blockPath.first, list.id, "Same container")
    }

    /// Multi-line paste into a heading: extra lines DEMOTE to body
    /// (Notion / Apple Notes convention — heading split is one heading
    /// + body paragraphs).
    func test_applyEdit_multiLinePaste_intoHeading_demotesExtras() {
        let h = Block(kind: .heading(level: 1, inline: [Inline(text: "Title")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [h]))

        index.applyEdit(replacing: NSRange(location: 5, length: 0), with: "\nA\nB")

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertEqual(index.entries[0].kind, .heading(level: 1), "First half stays heading")
        XCTAssertEqual(index.entries[1].kind, .paragraph, "Middle demotes to body")
        XCTAssertEqual(index.entries[2].kind, .paragraph, "Last demotes to body")
    }

    /// Cross-paragraph delete spanning ONE `\n`: two paragraphs fuse
    /// into one inheriting the predecessor's identity.
    func test_applyEdit_crossParagraphDelete_oneBoundary_fusesTwo() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "World")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2]))
        // Storage "Hello\nWorld". Delete range [3, 5) covers
        // "lo\nWo" (5 chars). Result: "Hel" + "rld" = "Helrld" (6 chars).
        index.applyEdit(replacing: NSRange(location: 3, length: 5), with: "")

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 6), "'Helrld' is 6 chars")
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "Predecessor's identity wins")
    }

    /// Multi-paragraph selection + Enter: the selection collapses, the
    /// post-selection tail becomes a new top-level paragraph.
    func test_applyEdit_multiParaSelectionPlusEnter_collapses() {
        let p1 = Block(kind: .paragraph(inline: [Inline(text: "AB")]))
        let p2 = Block(kind: .paragraph(inline: [Inline(text: "CD")]))
        let p3 = Block(kind: .paragraph(inline: [Inline(text: "EF")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p1, p2, p3]))
        // Storage: "AB\nCD\nEF". Range [1, 6) covers "B\nCD\nE".
        // Replace with "\n" → "A\nF".
        index.applyEdit(replacing: NSRange(location: 1, length: 6), with: "\n")

        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.entries[0].range, NSRange(location: 0, length: 1), "A")
        XCTAssertEqual(index.entries[0].blockPath, [p1.id], "First keeps identity")
        XCTAssertEqual(index.entries[1].range, NSRange(location: 2, length: 1), "F")
        XCTAssertNotEqual(index.entries[1].blockPath, [p3.id], "Last is fresh")
    }

    /// Phantom-tail (edit past the addressable index range) is a no-op.
    func test_applyEdit_pastLastParagraph_isNoOp() {
        let p = Block(kind: .paragraph(inline: [Inline(text: "Hi")]))
        var index = ParagraphIndex(document: RichTextDocument(blocks: [p]))
        let before = index.entries

        index.applyEdit(replacing: NSRange(location: 99, length: 0), with: "X")

        XCTAssertEqual(index.entries, before)
    }

    /// Empty index → no-op.
    func test_applyEdit_emptyIndex_isNoOp() {
        var index = ParagraphIndex()
        index.applyEdit(replacing: NSRange(location: 0, length: 0), with: "X")
        XCTAssertEqual(index.entries.count, 0)
    }
}
#endif
