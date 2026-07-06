#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import FromInk

/// Pins the `TextKitEditorView`'s flatten / parse-back contract.
///
/// The editor's load-bearing claims:
///
///   - Flatten produces one paragraph per leaf block, joined by `\n`.
///   - Each paragraph carries `.paragraphKind`, `.blockID`, and (where
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

    func test_flatten_paragraph_emitsParagraphKindAndBlockID() {
        let id = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id, kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Flatten emits one trailing `\n` per paragraph as the
        // chrome / line-fragment carrier (no trim — see flatten's
        // inline comment for why).
        XCTAssertEqual(result.attributed.string, "Hello\n")
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.paragraphKind] as? Int, ParagraphKind.paragraph.attributeValue)
        XCTAssertNil(attrs[.groupID], "Top-level paragraph has no group id")
        _ = id
    }

    func test_flatten_heading_emitsCorrectChrome() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 2, inline: [Inline(text: "Title")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.paragraphKind] as? Int, ParagraphKind.heading(level: 2).attributeValue)
    }

    func test_flatten_bulletList_emitsSharedGroupID() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "A")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "B")]))])
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(result.attributed.string, "A\nB\n")

        let firstAttrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        // Index 2 is the start of "B" (after "A\n").
        let secondAttrs = result.attributed.attributes(at: 2, effectiveRange: nil)
        XCTAssertEqual(firstAttrs[.paragraphKind] as? Int, ParagraphKind.bulletListItem.attributeValue)
        XCTAssertEqual(secondAttrs[.paragraphKind] as? Int, ParagraphKind.bulletListItem.attributeValue)
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
        XCTAssertEqual(firstAttrs[.paragraphKind] as? Int, ParagraphKind.orderedListItem.attributeValue)
        XCTAssertEqual(secondAttrs[.paragraphKind] as? Int, ParagraphKind.orderedListItem.attributeValue)
        XCTAssertEqual(firstAttrs[.groupID] as? UUID, secondAttrs[.groupID] as? UUID)
    }

    func test_flatten_blockquote_emitsBlockquoteParagraphChrome() {
        // Fix B7: blockquote children now emit .blockquoteParagraph
        // chrome (not .paragraph) so parse-back's grouping switch
        // recognizes them as blockquote-container children.
        let doc = RichTextDocument(blocks: [
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quote")]))
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.paragraphKind] as? Int, ParagraphKind.blockquoteParagraph.attributeValue)
        XCTAssertNotNil(attrs[.groupID])
    }

    func test_flatten_divider_emitsDividerChromeAndAnchorChar() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .divider)
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(result.attributed.string, "\u{00A0}\n")
        let attrs = result.attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.paragraphKind] as? Int, ParagraphKind.divider.attributeValue)
    }

    // MARK: - Parse-back tests deleted in Chunk 9 — parse-back itself
    // is gone, replaced by `documentFromIndex`. The `test_documentFromIndex_*`
    // suite below covers the equivalent round-trip shapes (paragraph,
    // heading, bullet list, ordered list, blockquote, code block,
    // divider, full-tree identity).

    // MARK: - documentFromIndex — the index-authoritative document builder

    /// Round-trip a body paragraph through documentFromIndex: identity
    /// stays stable (same Block.id in, same id out), inline runs survive.
    func test_documentFromIndex_paragraph_preservesIdAndInlineRuns() {
        let id = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id, kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        XCTAssertEqual(recovered.blocks.count, 1)
        XCTAssertEqual(recovered.blocks[0].id, id, "Leaf id from the index — no parseBack dedupe")
        guard case .paragraph(let inline) = recovered.blocks[0].kind else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(inline.map(\.text).joined(), "Hello")
    }

    /// Heading level (1-3) round-trips through the index.
    func test_documentFromIndex_heading_recoversLevel() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 2, inline: [Inline(text: "Title")]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        guard case .heading(let level, let inline) = recovered.blocks[0].kind else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(inline.map(\.text).joined(), "Title")
    }

    /// Consecutive `.bulletListItem` entries with the same container id
    /// regroup into one `bulletList` block. Both the container id AND
    /// every ListItem.id stay stable — the killer parseBack couldn't
    /// promise (containers got fresh UUIDs every call).
    func test_documentFromIndex_bulletList_preservesContainerAndItemIds() {
        let listID = UUID()
        let item1ID = UUID()
        let item2ID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: item1ID, content: [Block(kind: .paragraph(inline: [Inline(text: "A")]))]),
                ListItem(id: item2ID, content: [Block(kind: .paragraph(inline: [Inline(text: "B")]))])
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        XCTAssertEqual(recovered.blocks.count, 1)
        XCTAssertEqual(recovered.blocks[0].id, listID, "Container id stable across rebuild")
        guard case .bulletList(let items) = recovered.blocks[0].kind else {
            return XCTFail("Expected bulletList")
        }
        XCTAssertEqual(items.map(\.id), [item1ID, item2ID], "ListItem ids stable")
    }

    /// Same for ordered lists.
    func test_documentFromIndex_orderedList_preservesContainerAndItemIds() {
        let listID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "1st")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "2nd")]))])
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        XCTAssertEqual(recovered.blocks[0].id, listID)
        guard case .orderedList(let items) = recovered.blocks[0].kind else {
            return XCTFail("Expected orderedList")
        }
        XCTAssertEqual(items.count, 2)
    }

    /// Blockquote container id stays stable too.
    func test_documentFromIndex_blockquote_preservesContainerId() {
        let quoteID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: quoteID, kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quote")]))
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        XCTAssertEqual(recovered.blocks[0].id, quoteID)
        guard case .blockquote = recovered.blocks[0].kind else {
            return XCTFail("Expected blockquote")
        }
    }

    /// Code-block text + language hint round-trip through the index.
    func test_documentFromIndex_codeBlock_preservesTextAndLanguage() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .codeBlock(text: "let x = 1", languageHint: "swift"))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        guard case .codeBlock(let text, let hint) = recovered.blocks[0].kind else {
            return XCTFail("Expected codeBlock")
        }
        XCTAssertEqual(text, "let x = 1")
        XCTAssertEqual(hint, "swift")
    }

    /// Divider round-trips through the index.
    func test_documentFromIndex_divider_emitsDivider() {
        let doc = RichTextDocument(blocks: [Block(kind: .divider)])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )
        XCTAssertEqual(recovered.blocks.count, 1)
        guard case .divider = recovered.blocks[0].kind else {
            return XCTFail("Expected divider")
        }
    }

    /// **The key contract.** A full `document → flatten → documentFromIndex`
    /// round trip preserves every Block.id, every ListItem.id, and every
    /// container id. parseBack couldn't promise this because container
    /// Blocks got fresh UUIDs every call; `documentFromIndex` reads
    /// container ids straight from the index's `blockPath`.
    ///
    /// Inline marks aren't checked here because the existing
    /// `parseInlineRuns` recovers `.bold` / `.italic` from font traits —
    /// the heading's semibold serif comes back as an inline `.bold`
    /// mark, the blockquote's italic body font as `.italic`. That's a
    /// pre-existing limitation of the round trip (shared with parseBack)
    /// and out of scope for the identity invariant this test pins.
    func test_documentFromIndex_fullRoundTrip_preservesIdentity() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Title")])),
            Block(kind: .paragraph(inline: [Inline(text: "Body")])),
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "row A")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "row B")]))])
            ])),
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "quoted")]))
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flat.attributed
        )

        // Same top-level ids in the same order.
        XCTAssertEqual(recovered.blocks.map(\.id), doc.blocks.map(\.id))

        // bulletList: container id stable, item ids stable.
        guard case .bulletList(let origItems) = doc.blocks[2].kind,
              case .bulletList(let recItems) = recovered.blocks[2].kind else {
            return XCTFail("Expected bulletList at index 2")
        }
        XCTAssertEqual(recItems.map(\.id), origItems.map(\.id), "ListItem ids preserved")
        XCTAssertEqual(
            recItems.map { $0.content.first?.id },
            origItems.map { $0.content.first?.id },
            "List items' inner paragraph ids preserved"
        )

        // blockquote: container id stable, child paragraph id stable.
        guard case .blockquote(let origChildren) = doc.blocks[3].kind,
              case .blockquote(let recChildren) = recovered.blocks[3].kind else {
            return XCTFail("Expected blockquote at index 3")
        }
        XCTAssertEqual(recChildren.map(\.id), origChildren.map(\.id), "Blockquote child ids preserved")
    }

    /// `paragraphCount(in:)` powers the index-vs-storage alignment gate
    /// in syncDocumentFromStorage. Pin the boundary cases the gate
    /// relies on.
    func test_paragraphCount_emptyStorage_isZero() {
        XCTAssertEqual(TextKitEditorView.paragraphCount(in: NSAttributedString()), 0)
    }

    func test_paragraphCount_flattenOutput_matchesIndexEntries() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "A")])),
            Block(kind: .paragraph(inline: [Inline(text: "B")])),
            Block(kind: .paragraph(inline: [Inline(text: "C")]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(TextKitEditorView.paragraphCount(in: flat.attributed), 3)
        XCTAssertEqual(
            TextKitEditorView.paragraphCount(in: flat.attributed),
            ParagraphIndex(document: doc).entries.count,
            "Storage paragraph count and index entry count must agree for documentFromIndex"
        )
    }

    func test_paragraphCount_unterminatedTail_counts() {
        // A storage that doesn't end with `\n` (rare but possible
        // mid-edit) still counts its tail paragraph.
        let s = NSAttributedString(string: "A\nB")
        XCTAssertEqual(TextKitEditorView.paragraphCount(in: s), 2)
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
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flattened.attributed
        )
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
            paragraphIndex: ParagraphIndex(document: doc),
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
        _ = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Range at offset 8 (inside "Second" — "Se|cond"), length 0
        let nsRange = NSRange(location: 8, length: 0)
        let bridged = TextKitEditorView.selection(
            forNSRange: nsRange,
            paragraphIndex: ParagraphIndex(document: doc)
        )
        XCTAssertEqual(bridged.path, [id2])
        XCTAssertEqual(bridged.startUTF16, 2)
        XCTAssertEqual(bridged.endUTF16, 2)
    }

    // MARK: - B1 — parse-back dedupes colliding block IDs (DELETED in
    // Chunk 9). `.blockID` attribute writes are gone, so duplicate ids
    // can no longer appear in storage; identity lives in the side-
    // channel `ParagraphIndex` UIKit can't touch.

    // MARK: - B2 — highlight + code marks round-trip

    func test_highlightMark_roundTrips_viaCustomKey() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "Plain "),
                Inline(text: "yellow", marks: [.highlight(.yellow)]),
                Inline(text: " end")
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flattened.attributed
        )
        guard case .paragraph(let inline) = recovered.blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        // Locate the highlighted run.
        let highlightRun = inline.first { $0.marks.contains(where: { mark in
            if case .highlight = mark { return true } else { return false }
        }) }
        XCTAssertNotNil(highlightRun, "Highlight mark must survive flatten → parse-back")
        XCTAssertEqual(highlightRun?.text, "yellow")
        XCTAssertEqual(highlightRun?.marks, [.highlight(.yellow)])
    }

    func test_codeMark_roundTrips_viaCustomKey_andDoesNotEmitItalicFromMonospaceTraits() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "Use "),
                Inline(text: "let x = 1", marks: [.code])
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flattened.attributed
        )
        guard case .paragraph(let inline) = recovered.blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        let codeRun = inline.first { $0.marks.contains(.code) }
        XCTAssertNotNil(codeRun, "Code mark must survive flatten → parse-back")
        XCTAssertEqual(codeRun?.text, "let x = 1")
        XCTAssertEqual(codeRun?.marks, [.code], "Code mark only — NOT bold/italic inferred from monospace font")
    }

    // MARK: - B7 — blockquote container round-trips

    func test_parseBack_blockquote_preservesContainer() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quoted")]))
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flattened.attributed
        )
        XCTAssertEqual(recovered.blocks.count, 1)
        guard case .blockquote(let children) = recovered.blocks[0].kind else {
            XCTFail("Blockquote container must survive round-trip (B7)")
            return
        }
        XCTAssertEqual(children.count, 1)
        guard case .paragraph(let inline) = children[0].kind else {
            XCTFail("Inner paragraph must survive")
            return
        }
        XCTAssertEqual(inline.first?.text, "Quoted")
    }

    func test_parseBack_blockquoteWithMultipleParagraphs_preservesAllChildren() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "First")])),
                Block(kind: .paragraph(inline: [Inline(text: "Second")]))
            ]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flattened.attributed
        )
        guard case .blockquote(let children) = recovered.blocks[0].kind else {
            XCTFail("Expected blockquote")
            return
        }
        XCTAssertEqual(children.count, 2)
    }

    // MARK: - S1 — codeBlock languageHint round-trips

    func test_codeBlock_languageHint_roundTrips() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .codeBlock(text: "let x = 1", languageHint: "swift"))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc),
            storage: flattened.attributed
        )
        guard case .codeBlock(let text, let hint) = recovered.blocks[0].kind else {
            XCTFail("Expected codeBlock")
            return
        }
        XCTAssertEqual(text, "let x = 1")
        XCTAssertEqual(hint, "swift", "Language hint must survive flatten → parse-back")
    }

    // MARK: - S2 — selection bridge clamps multi-paragraph end

    func test_selection_forNSRange_spanningTwoParagraphs_clampsToFirstParagraph() {
        let id1 = UUID()
        let id2 = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id1, kind: .paragraph(inline: [Inline(text: "First")])),
            Block(id: id2, kind: .paragraph(inline: [Inline(text: "Second")]))
        ])
        _ = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Selection from offset 2 through 9 ("rst\nSec") — spans paragraphs.
        let nsRange = NSRange(location: 2, length: 7)
        let bridged = TextKitEditorView.selection(
            forNSRange: nsRange,
            paragraphIndex: ParagraphIndex(document: doc)
        )
        XCTAssertEqual(bridged.path, [id1], "Selection's path is the FIRST paragraph it intersects")
        XCTAssertEqual(bridged.startUTF16, 2)
        XCTAssertEqual(bridged.endUTF16, 5, "endUTF16 clamps to first paragraph's text length (5)")
    }

    // MARK: - S2 — nsRange clamps stale-offset overruns

    // MARK: - Keyboard shortcuts — UIKeyCommand vocabulary

    func test_blockTreeTextView_exposesInlineFormatShortcuts() {
        let textView = BlockTreeTextView()
        let commands = textView.keyCommands ?? []
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "b" && cmd.modifierFlags == .command
        }, "⌘B should appear in keyCommands")
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "i" && cmd.modifierFlags == .command
        }, "⌘I should appear in keyCommands")
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "u" && cmd.modifierFlags == .command
        }, "⌘U should appear in keyCommands")
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "x" && cmd.modifierFlags == [.command, .shift]
        }, "⌘⇧X should appear in keyCommands for strikethrough")
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "e" && cmd.modifierFlags == .command
        }, "⌘E should appear in keyCommands for code")
    }

    func test_blockTreeTextView_exposesBlockFormatShortcuts() {
        let textView = BlockTreeTextView()
        let commands = textView.keyCommands ?? []
        for digit in ["0", "1", "2", "3"] {
            XCTAssertTrue(commands.contains { cmd in
                cmd.input == digit && cmd.modifierFlags == [.command, .alternate]
            }, "⌘⌥\(digit) should appear in keyCommands")
        }
    }

    func test_blockTreeTextView_exposesListShortcuts() {
        // S2: ⌘⇧7 numbered list, ⌘⇧8 bulleted list.
        let textView = BlockTreeTextView()
        let commands = textView.keyCommands ?? []
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "7" && cmd.modifierFlags == [.command, .shift]
        }, "⌘⇧7 should appear in keyCommands for numbered list")
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "8" && cmd.modifierFlags == [.command, .shift]
        }, "⌘⇧8 should appear in keyCommands for bulleted list")
    }

    func test_blockTreeTextView_exposesSlashPaletteShortcut() {
        let textView = BlockTreeTextView()
        let commands = textView.keyCommands ?? []
        XCTAssertTrue(commands.contains { cmd in
            cmd.input == "/" && cmd.modifierFlags == [.command, .shift]
        }, "⌘⇧/ should appear in keyCommands for slash palette")
    }

    func test_blockTreeTextView_keyCommands_allWantPriorityOverSystemBehavior() {
        // Regression: every shortcut must trump UITextView's defaults
        // — otherwise ⌘B/I/U fall through to its built-in rich-text
        // path which doesn't use our reducer actions.
        let textView = BlockTreeTextView()
        let commands = textView.keyCommands ?? []
        XCTAssertFalse(commands.isEmpty, "keyCommands must not be empty")
        for command in commands {
            XCTAssertTrue(
                command.wantsPriorityOverSystemBehavior,
                "Every command must set wantsPriorityOverSystemBehavior (got false on \(command.input ?? "?"))"
            )
        }
    }

    func test_blockTreeTextView_keyCommands_allHaveDiscoverabilityTitles() {
        // Hold-⌘ HUD on iPad with hardware keyboard reads these.
        let textView = BlockTreeTextView()
        let commands = textView.keyCommands ?? []
        for command in commands {
            XCTAssertFalse(
                (command.discoverabilityTitle ?? "").isEmpty,
                "Every command must set a discoverabilityTitle (got empty on \(command.input ?? "?"))"
            )
        }
    }

    func test_blockTreeTextView_keyCommands_areCached_returnsIdenticalArrayBetweenCalls() {
        // M1: caching avoids per-call allocation of 12 UIKeyCommand
        // instances. Identity check confirms the same array is
        // returned, not a fresh copy each time.
        let textView = BlockTreeTextView()
        let first = textView.keyCommands ?? []
        let second = textView.keyCommands ?? []
        XCTAssertEqual(first.count, second.count)
        for (a, b) in zip(first, second) {
            XCTAssertTrue(a === b, "Cached keyCommands should return identical UIKeyCommand instances")
        }
    }

    func test_blockTreeTextView_onEditorCommand_firesForBold() {
        let textView = BlockTreeTextView()
        var receivedCommands: [EditorCommand] = []
        textView.onEditorCommand = { receivedCommands.append($0) }
        textView.perform(#selector(BlockTreeTextView.formatBold(_:)), with: nil)
        XCTAssertEqual(receivedCommands, [.toggleBold])
    }

    func test_blockTreeTextView_onEditorCommand_firesForHeadingLevels() {
        let textView = BlockTreeTextView()
        var receivedCommands: [EditorCommand] = []
        textView.onEditorCommand = { receivedCommands.append($0) }
        textView.perform(#selector(BlockTreeTextView.applyHeading1(_:)), with: nil)
        textView.perform(#selector(BlockTreeTextView.applyHeading2(_:)), with: nil)
        textView.perform(#selector(BlockTreeTextView.applyHeading3(_:)), with: nil)
        textView.perform(#selector(BlockTreeTextView.applyBodyParagraph(_:)), with: nil)
        XCTAssertEqual(receivedCommands, [
            .applyHeading(level: 1),
            .applyHeading(level: 2),
            .applyHeading(level: 3),
            .applyBody
        ])
    }

    // MARK: - evaluateSlashTrigger (pure)

    func test_slashTrigger_emptyDocument_armsAtZero() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 0, length: 0),
            currentText: ""
        )
        XCTAssertEqual(result, .armed(location: 0))
    }

    func test_slashTrigger_afterNewline_arms() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 6, length: 0),
            currentText: "Hello\n"
        )
        XCTAssertEqual(result, .armed(location: 6))
    }

    func test_slashTrigger_afterSpace_arms() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 6, length: 0),
            currentText: "Hello "
        )
        XCTAssertEqual(result, .armed(location: 6))
    }

    func test_slashTrigger_afterTab_arms() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 6, length: 0),
            currentText: "Hello\t"
        )
        XCTAssertEqual(result, .armed(location: 6), "Tab is whitespace — should arm")
    }

    func test_slashTrigger_afterNonBreakingSpace_arms() {
        // U+00A0 NO-BREAK SPACE — common in PDF / RTF imports.
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 6, length: 0),
            currentText: "Hello\u{00A0}"
        )
        XCTAssertEqual(result, .armed(location: 6), "Non-breaking space is whitespace")
    }

    func test_slashTrigger_afterIdeographicSpace_arms() {
        // U+3000 IDEOGRAPHIC SPACE — common on CJK keyboards.
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 6, length: 0),
            currentText: "Hello\u{3000}"
        )
        XCTAssertEqual(result, .armed(location: 6), "Ideographic space is whitespace")
    }

    func test_slashTrigger_midWord_isClear() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 5, length: 0),
            currentText: "Hello"
        )
        XCTAssertEqual(result, .clear, "Slash after 'Hello' (no boundary) must not arm")
    }

    func test_slashTrigger_afterEmoji_isClear_notACrash() {
        // 👋 is U+1F44B — a surrogate pair (2 UTF-16 code units).
        // Pre-fix: substringing the lone trailing surrogate would
        // either crash or return an invalid scalar.
        // Post-fix: Character-based evaluation sees the FULL emoji
        // grapheme, recognizes it as non-whitespace, returns .clear.
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 2, length: 0),
            currentText: "👋"
        )
        XCTAssertEqual(result, .clear, "Slash after emoji is not at a boundary")
    }

    func test_slashTrigger_afterEmojiAndSpace_arms() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 3, length: 0),
            currentText: "👋 "
        )
        XCTAssertEqual(result, .armed(location: 3), "Slash after emoji + space arms")
    }

    func test_slashTrigger_replacementTextIsNotSlash_clears() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "a",
            replacementRange: NSRange(location: 0, length: 0),
            currentText: ""
        )
        XCTAssertEqual(result, .clear, "Any non-slash text clears pending")
    }

    func test_slashTrigger_multiCharReplacement_isClear() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "Hi /",
            replacementRange: NSRange(location: 0, length: 0),
            currentText: ""
        )
        XCTAssertEqual(result, .clear, "Paste / autocorrect / predictive multi-char inputs don't arm (v1 limitation)")
    }

    func test_slashTrigger_outOfRangeLocation_isClear_notACrash() {
        let result = TextKitEditorView.evaluateSlashTrigger(
            replacementText: "/",
            replacementRange: NSRange(location: 99, length: 0),
            currentText: "Hi"
        )
        XCTAssertEqual(result, .clear)
    }

    func test_blockTreeTextView_onEditorCommand_firesForListShortcuts() {
        let textView = BlockTreeTextView()
        var receivedCommands: [EditorCommand] = []
        textView.onEditorCommand = { receivedCommands.append($0) }
        textView.perform(#selector(BlockTreeTextView.applyBulletedList(_:)), with: nil)
        textView.perform(#selector(BlockTreeTextView.applyNumberedList(_:)), with: nil)
        XCTAssertEqual(receivedCommands, [.applyBulletedList, .applyNumberedList])
    }

    func test_nsRange_forSelection_outOfRangeOffsets_areClamped() {
        let id = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: id, kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Stale selection with offsets way past leaf length.
        let selection = BlockTreeSelection(path: [id], startUTF16: 99, endUTF16: 200)
        let nsRange = TextKitEditorView.nsRange(
            for: selection,
            paragraphIndex: ParagraphIndex(document: doc),
            totalLength: flattened.attributed.length
        )
        XCTAssertNotNil(nsRange)
        XCTAssertEqual(nsRange?.location, 5, "Start clamps to leaf's text length")
        XCTAssertEqual(nsRange?.length, 0, "End clamps to leaf's text length too")
    }

    // MARK: - shouldExitList (pure)
    //
    // Pins the contract for the empty-list-item Enter detector.
    // The Coordinator's `shouldChangeTextIn` only suppresses the
    // newline when this function says yes; everything else falls
    // through to the default Enter behavior. Same testability
    // pattern as `evaluateSlashTrigger`.

    func test_shouldExitList_emptyBulletItem_atParagraphLeaf_isTrue() {
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: leafID, kind: .paragraph(inline: []))])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 0, endUTF16: 0)
        XCTAssertTrue(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 0),
            selection: selection,
            document: doc
        ))
    }

    func test_shouldExitList_emptyOrderedItem_isTrue() {
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .orderedList(items: [
                ListItem(id: UUID(), content: [Block(id: leafID, kind: .paragraph(inline: []))])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 0, endUTF16: 0)
        XCTAssertTrue(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 0),
            selection: selection,
            document: doc
        ))
    }

    func test_shouldExitList_nonEmptyListItem_isFalse() {
        // Non-empty list item Enter is a normal list-split — DO NOT
        // suppress; let UIKit insert the newline so a fresh item
        // gets created.
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [
                    Block(id: leafID, kind: .paragraph(inline: [Inline(text: "hello")]))
                ])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 5, endUTF16: 5)
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 5, length: 0),
            selection: selection,
            document: doc
        ))
    }

    func test_shouldExitList_topLevelParagraph_isFalse() {
        // No list container above this leaf — Enter on an empty
        // body paragraph should NOT exit anything.
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: leafID, kind: .paragraph(inline: []))
        ])
        let selection = BlockTreeSelection(path: [leafID], startUTF16: 0, endUTF16: 0)
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 0),
            selection: selection,
            document: doc
        ))
    }

    func test_shouldExitList_nonNewlineReplacement_isFalse() {
        // A regular character on an empty list item should NOT
        // exit — that's just typing into the item.
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: leafID, kind: .paragraph(inline: []))])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 0, endUTF16: 0)
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "a",
            replacementRange: NSRange(location: 0, length: 0),
            selection: selection,
            document: doc
        ))
    }

    func test_shouldExitList_newlineReplacingSelection_isFalse() {
        // Enter while a multi-char selection is active means
        // "delete selection then newline" — not an exit attempt,
        // even if the selection is inside an empty list item
        // (which is itself unusual but defensible).
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: leafID, kind: .paragraph(inline: []))])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 0, endUTF16: 0)
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 3),
            selection: selection,
            document: doc
        ))
    }

    // MARK: - typingAttributesFromDocument (L1 fix)
    //
    // When `applyBlockFormat(.bulletedList)` runs against an
    // empty paragraph, the resulting flatten is zero-length and
    // `refreshTypingAttributes` would otherwise no-op — leaving
    // the user's next keystroke with the pre-wrap paragraph
    // chrome and dissolving the list on the next parse-back.
    // The fallback path resolves chrome from the document at the
    // selection's path; tests pin all four container shapes.

    func test_typingAttributesFromDocument_bulletListItemLeaf_returnsBulletChrome() {
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: leafID, kind: .paragraph(inline: []))])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 0, endUTF16: 0)
        let attrs = TextKitEditorView.typingAttributesFromDocument(
            document: doc,
            selection: selection,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        XCTAssertEqual(attrs?[.paragraphKind] as? Int, ParagraphKind.bulletListItem.attributeValue)
        XCTAssertNotNil(attrs?[.groupID] as? UUID,
                        "List-container kind must carry a groupID so the layout manager numbers ordered items correctly")
        _ = leafID
    }

    func test_typingAttributesFromDocument_orderedListItemLeaf_returnsOrderedChrome() {
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .orderedList(items: [
                ListItem(id: UUID(), content: [Block(id: leafID, kind: .paragraph(inline: []))])
            ]))
        ])
        let selection = BlockTreeSelection(path: [listID, leafID], startUTF16: 0, endUTF16: 0)
        let attrs = TextKitEditorView.typingAttributesFromDocument(
            document: doc,
            selection: selection,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        XCTAssertEqual(attrs?[.paragraphKind] as? Int, ParagraphKind.orderedListItem.attributeValue)
        XCTAssertNotNil(attrs?[.groupID] as? UUID)
    }

    func test_typingAttributesFromDocument_blockquoteParagraphLeaf_returnsBlockquoteChrome() {
        let quoteID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: quoteID, kind: .blockquote(children: [
                Block(id: leafID, kind: .paragraph(inline: []))
            ]))
        ])
        let selection = BlockTreeSelection(path: [quoteID, leafID], startUTF16: 0, endUTF16: 0)
        let attrs = TextKitEditorView.typingAttributesFromDocument(
            document: doc,
            selection: selection,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        XCTAssertEqual(attrs?[.paragraphKind] as? Int, ParagraphKind.blockquoteParagraph.attributeValue)
        XCTAssertNotNil(attrs?[.groupID] as? UUID)
    }

    func test_typingAttributesFromDocument_topLevelHeading_returnsHeadingChrome() {
        // Top-level leaves use their OWN kind's chrome — no
        // container to override.
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: leafID, kind: .heading(level: 2, inline: []))
        ])
        let selection = BlockTreeSelection(path: [leafID], startUTF16: 0, endUTF16: 0)
        let attrs = TextKitEditorView.typingAttributesFromDocument(
            document: doc,
            selection: selection,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        XCTAssertEqual(attrs?[.paragraphKind] as? Int, ParagraphKind.heading(level: 2).attributeValue)
        XCTAssertNil(attrs?[.groupID] as? UUID,
                     "Top-level leaves don't need a groupID — they're not part of a grouped container")
    }

    func test_typingAttributesFromDocument_unresolvablePath_returnsNil() {
        let doc = RichTextDocument(blocks: [
            Block(id: UUID(), kind: .paragraph(inline: []))
        ])
        let selection = BlockTreeSelection(path: [UUID()], startUTF16: 0, endUTF16: 0)
        XCTAssertNil(TextKitEditorView.typingAttributesFromDocument(
            document: doc,
            selection: selection,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        ))
    }

    func test_shouldExitList_emptySelectionPath_isFalse() {
        // Stale selection where path didn't resolve — no list to
        // exit. Defends against the editor firing the command
        // before selection has been synced.
        let doc = RichTextDocument(blocks: [])
        let selection = BlockTreeSelection()
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 0),
            selection: selection,
            document: doc
        ))
    }

    // MARK: - Ordered-list ordinal

    func test_orderedItemOrdinal_countsPositionWithinGroup_independentOfDrawRange() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "one")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "two")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "three")]))])
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let starts = result.flattenMap.map(\.nsRange.location)
        XCTAssertEqual(starts.count, 3)

        for (index, start) in starts.enumerated() {
            let groupID = result.attributed.attribute(.groupID, at: start, effectiveRange: nil) as? UUID
            // The ordinal derives from storage position alone — the
            // draw-call's glyph range plays no part. Asking for item
            // N's ordinal without having "drawn" items 0..<N first is
            // exactly the scrolled-mid-list case that the old per-draw
            // running counter got wrong (item 11 rendered as "1.").
            XCTAssertEqual(
                BlockDecoratingLayoutManager.orderedItemOrdinal(
                    in: result.attributed,
                    paragraphStart: start,
                    groupID: groupID
                ),
                index + 1
            )
        }
    }

    func test_orderedItemOrdinal_restartsAcrossSeparateLists() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "a1")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "a2")]))])
            ])),
            Block(kind: .paragraph(inline: [Inline(text: "interlude")])),
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "b1")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "b2")]))])
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let starts = result.flattenMap.map(\.nsRange.location)
        XCTAssertEqual(starts.count, 5)

        let secondListFirst = starts[3]
        let secondListSecond = starts[4]
        let groupID = result.attributed.attribute(.groupID, at: secondListFirst, effectiveRange: nil) as? UUID
        XCTAssertEqual(
            BlockDecoratingLayoutManager.orderedItemOrdinal(
                in: result.attributed, paragraphStart: secondListFirst, groupID: groupID
            ),
            1,
            "A fresh group restarts at 1 — the walk stops at the interlude paragraph"
        )
        XCTAssertEqual(
            BlockDecoratingLayoutManager.orderedItemOrdinal(
                in: result.attributed, paragraphStart: secondListSecond, groupID: groupID
            ),
            2
        )
    }

    // MARK: - Storage-side selection bridge

    func test_bridgeSelection_resolvesNestedLeafPathAndParagraphLocalOffsets() {
        let listLeafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "intro")])),
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(id: listLeafID, kind: .paragraph(inline: [Inline(text: "item one")]))])
            ]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)

        // "intro\nitem one\n" — caret inside "item one" at its
        // local offset 5 (absolute 6 + 5 = 11).
        let bridged = TextKitEditorView.bridgeSelection(
            storage: result.attributed,
            selectedRange: NSRange(location: 11, length: 3),
            paragraphIndex: ParagraphIndex(document: doc)
        )
        XCTAssertEqual(bridged.path, [doc.blocks[1].id, listLeafID], "Path includes the list container, skips the ListItem id")
        XCTAssertEqual(bridged.startUTF16, 5)
        XCTAssertEqual(bridged.endUTF16, 8)
    }

    func test_bridgeSelection_multiParagraphRange_clampsToHostLeaf() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "first")])),
            Block(kind: .paragraph(inline: [Inline(text: "second")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)

        // Drag from "fi|rst" into "second" — clamps to first leaf
        // (single-leaf selection invariant, fix S2).
        let bridged = TextKitEditorView.bridgeSelection(
            storage: result.attributed,
            selectedRange: NSRange(location: 2, length: 8),
            paragraphIndex: ParagraphIndex(document: doc)
        )
        XCTAssertEqual(bridged.path, [doc.blocks[0].id])
        XCTAssertEqual(bridged.startUTF16, 2)
        XCTAssertEqual(bridged.endUTF16, 5, "End clamps to the host paragraph's length")
    }

    func test_bridgeSelection_caretPastFinalNewline_returnsUnset() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "tail")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let bridged = TextKitEditorView.bridgeSelection(
            storage: result.attributed,
            selectedRange: NSRange(location: result.attributed.length, length: 0),
            paragraphIndex: ParagraphIndex(document: doc)
        )
        XCTAssertTrue(bridged.isUnset, "Phantom line after the final \\n matches the old map-based bridge's unset contract")
    }

    /// Identity comes from `ParagraphIndex` — the side-channel UIKit
    /// can't touch — never from per-character storage attributes. Hand
    /// a divergent index (a different path for the same range) and
    /// prove the bridge returns the index's path.
    func test_bridgeSelection_takesPathFromParagraphIndex() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let indexLeafID = UUID()
        let index = ParagraphIndex(entries: [
            .init(range: NSRange(location: 0, length: 5), blockPath: [indexLeafID], kind: .paragraph)
        ])

        let bridged = TextKitEditorView.bridgeSelection(
            storage: result.attributed,
            selectedRange: NSRange(location: 2, length: 0),
            paragraphIndex: index
        )
        XCTAssertEqual(bridged.path, [indexLeafID], "Identity comes from the index, never from storage attributes")
        XCTAssertEqual(bridged.startUTF16, 2)
    }

    /// Stale-index window (paragraph count or ranges disagree with the
    /// live storage during a complex structural edit the incremental
    /// ops don't cover yet) → unset selection. Commit 6 removed the
    /// `.blockID` attribute fallback that used to silently resolve
    /// here; the unset return value is the caller's signal to skip the
    /// override and wait for the next sync.
    func test_bridgeSelection_staleIndex_returnsUnset() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let result = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)

        let bridged = TextKitEditorView.bridgeSelection(
            storage: result.attributed,
            selectedRange: NSRange(location: 2, length: 0),
            paragraphIndex: ParagraphIndex()  // stale/empty — no entry covers the caret
        )
        XCTAssertTrue(bridged.isUnset, "Stale index returns unset — no attribute fallback")
    }

    // MARK: - Paragraph identity hygiene (DELETED in Chunk 9)
    //
    // `paragraphIdentityFixups`, `applyParagraphIdentityFixups`, and
    // `tailParagraphNeedsIdentityFixup` are gone. Their job was to
    // detect duplicate `.blockID` storage attributes and mint fresh
    // ids — a workaround for the `typingAttributes` corruption that
    // the side-channel ParagraphIndex architecture made structurally
    // impossible. `ParagraphIndex.applyEdit` is the sole identity
    // arbiter now, and the index's entries can't have duplicates by
    // construction.

    // MARK: - Storage-side exit-list + slash filter

    func test_shouldExitList_storageBased_emptyListItem_true_nonEmpty_false() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "full")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: []))])
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // "full\n\n" — the empty item's paragraph is at location 5.
        XCTAssertTrue(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 5, length: 0),
            storage: flat.attributed,
            paragraphIndex: ParagraphIndex(document: doc)
        ))
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 2, length: 0),
            storage: flat.attributed,
            paragraphIndex: ParagraphIndex(document: doc)
        ), "Non-empty list item gets the native Enter (split into a new row)")
    }

    /// Kind comes from ParagraphIndex, not `.paragraphKind`. Flatten a
    /// plain (non-list) empty paragraph but hand an index that calls it
    /// a bullet item — shouldExitList must follow the INDEX (true).
    func test_shouldExitList_storageBased_prefersParagraphIndexKind() {
        let doc = RichTextDocument(blocks: [Block(kind: .paragraph(inline: []))])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let index = ParagraphIndex(entries: [
            .init(range: NSRange(location: 0, length: 0), blockPath: [UUID()], kind: .bulletListItem)
        ])
        XCTAssertTrue(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 0),
            storage: flat.attributed,
            paragraphIndex: index
        ), "Index kind (bulletListItem) drives the decision over the .paragraphKind attribute (paragraph)")
    }

    /// When the index can't name the paragraph (empty/stale), fall back
    /// to the `.paragraphKind` probe and still exit on an empty list item.
    func test_shouldExitList_storageBased_fallsBackToChromeWhenIndexStale() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [ListItem(content: [Block(kind: .paragraph(inline: []))])]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertTrue(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: 0, length: 0),
            storage: flat.attributed,
            paragraphIndex: ParagraphIndex()  // stale/empty
        ), "Attribute fallback still detects the empty bullet item")
    }

    // MARK: - shouldOutdentOnBackspace (pure)

    func test_shouldOutdentOnBackspace_emptyBulletItem_atTop_isTrue() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [ListItem(content: [Block(kind: .paragraph(inline: []))])]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Lone empty bullet item: storage "\n", caret at offset 0.
        XCTAssertTrue(TextKitEditorView.shouldOutdentOnBackspace(
            storage: flat.attributed,
            selectedRange: NSRange(location: 0, length: 0),
            paragraphIndex: ParagraphIndex(document: doc)
        ))
    }

    func test_shouldOutdentOnBackspace_emptyOrderedItem_isTrue() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "a")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: []))])
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // "a\n\n" — the empty second item's paragraph starts at 2.
        XCTAssertTrue(TextKitEditorView.shouldOutdentOnBackspace(
            storage: flat.attributed,
            selectedRange: NSRange(location: 2, length: 0),
            paragraphIndex: ParagraphIndex(document: doc)
        ))
    }

    func test_shouldOutdentOnBackspace_nonEmptyListItem_isFalse() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "x")]))])]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Caret at the start of a NON-empty item — native merge, no outdent.
        XCTAssertFalse(TextKitEditorView.shouldOutdentOnBackspace(
            storage: flat.attributed,
            selectedRange: NSRange(location: 0, length: 0),
            paragraphIndex: ParagraphIndex(document: doc)
        ))
    }

    func test_shouldOutdentOnBackspace_emptyTopLevelParagraph_isFalse() {
        let doc = RichTextDocument(blocks: [Block(kind: .paragraph(inline: []))])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertFalse(TextKitEditorView.shouldOutdentOnBackspace(
            storage: flat.attributed,
            selectedRange: NSRange(location: 0, length: 0),
            paragraphIndex: ParagraphIndex(document: doc)
        ), "An empty body paragraph has no list indent to escape")
    }

    func test_shouldOutdentOnBackspace_nonZeroSelection_isFalse() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "ab")]))])]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertFalse(TextKitEditorView.shouldOutdentOnBackspace(
            storage: flat.attributed,
            selectedRange: NSRange(location: 0, length: 2),
            paragraphIndex: ParagraphIndex(document: doc)
        ), "A range deletion is a normal delete, not an outdent")
    }

    // MARK: - typingAttributesPreservingChrome (font follows chrome)

    func test_typingAttributesPreservingChrome_emptyHeading_typesHeadingFont() {
        let doc = RichTextDocument(blocks: [Block(kind: .heading(level: 1, inline: []))])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // What UIKit hands us on an empty heading line: body font, because
        // there's no preceding glyph to inherit the heading font from.
        let derived: [NSAttributedString.Key: Any] = [.font: bodyFont]

        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: derived,
            storage: flat.attributed,
            caretLocation: 0,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )

        XCTAssertEqual((merged[.font] as? UIFont)?.pointSize, 28,
                       "Typing in an empty heading must inherit the 28pt heading font, not body")
        XCTAssertEqual(merged[.paragraphKind] as? Int, ParagraphKind.heading(level: 1).attributeValue)
    }

    func test_typingAttributesPreservingChrome_bodyParagraph_staysBodyFont() {
        let doc = RichTextDocument(blocks: [Block(kind: .paragraph(inline: [Inline(text: "Hi")]))])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)

        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: [.font: bodyFont],
            storage: flat.attributed,
            caretLocation: 2,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )

        XCTAssertEqual((merged[.font] as? UIFont)?.pointSize, bodyFont.pointSize)
    }

    func test_typingAttributesPreservingChrome_preservesBoldTraitOnHeading() {
        // Heading whose text is bold — typing at the end should stay
        // bold AND heading-sized (chrome base font + preserved trait).
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Hi", marks: [.bold])]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)

        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: [.font: bodyFont],
            storage: flat.attributed,
            caretLocation: 2,  // end of "Hi"
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )

        let font = merged[.font] as? UIFont
        XCTAssertEqual(font?.pointSize, 28, "Stays heading-sized")
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                      "Preceding bold trait continues")
    }

    func test_slashFilter_returnsTextAfterTrigger_andNilWhenTriggerGone() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "see /head below")]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertEqual(
            TextKitEditorView.slashFilter(storage: flat.attributed, triggerLocation: 4),
            "head below",
            "Filter is the slice from after the trigger to the paragraph end"
        )
        XCTAssertNil(
            TextKitEditorView.slashFilter(storage: flat.attributed, triggerLocation: 0),
            "Location no longer holding a `/` dismisses"
        )
    }

    func test_newlineCount_countsParagraphTerminators() {
        XCTAssertEqual(TextKitEditorView.newlineCount(in: "" as NSString), 0)
        XCTAssertEqual(TextKitEditorView.newlineCount(in: "abc" as NSString), 0)
        XCTAssertEqual(TextKitEditorView.newlineCount(in: "a\nb\nc\n" as NSString), 3)
    }

    // MARK: - Reflow on bounds change (rotation / Split View resize)

    /// The editor must reflow to the available width whenever its bounds
    /// change — device rotation, iPad Split View / Stage Manager resize.
    /// `BlockTreeTextView.layoutSubviews` pins the text container width to
    /// the available content width on every layout pass (the production
    /// stack disables `widthTracksTextView`; here we mirror that so the
    /// test exercises the subclass's width management, not UIKit's
    /// automatic tracking). See text experience EDD §6.6.
    func test_blockTreeTextView_reflowsContainerWidth_onBoundsChange() {
        let textView = BlockTreeTextView()
        // Mirror the production container config (makeUIView): width is
        // managed by the subclass, no automatic tracking, zero inset/padding.
        textView.textContainer.widthTracksTextView = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // Portrait-sized bounds.
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        textView.layoutIfNeeded()
        XCTAssertEqual(
            textView.textContainer.size.width, 320, accuracy: 0.5,
            "Container width tracks the available width in the initial (portrait) layout"
        )

        // Rotate to a wider, landscape-sized bounds — the column must widen
        // to use the new available width rather than stay frozen at 320.
        textView.frame = CGRect(x: 0, y: 0, width: 768, height: 480)
        textView.layoutIfNeeded()
        XCTAssertEqual(
            textView.textContainer.size.width, 768, accuracy: 0.5,
            "Container reflows to the new available width after a bounds (rotation) change"
        )
    }

    // MARK: - Structural traits vs. inline marks (Fix 1)

    /// A kind's intrinsic typography traits (heading weight, blockquote
    /// slant) are reported by `structuralInlineTraits`; body/list kinds
    /// contribute none. These are the traits subtracted before a font's
    /// bold/italic is read as an explicit inline mark.
    func test_structuralInlineTraits_headingBold_blockquoteItalic_bodyEmpty() {
        XCTAssertTrue(
            TextKitEditorView.structuralInlineTraits(for: .heading(level: 1)).contains(.traitBold),
            "Heading's semibold weight is a structural bold trait"
        )
        XCTAssertTrue(
            TextKitEditorView.structuralInlineTraits(for: .blockquoteParagraph).contains(.traitItalic),
            "Blockquote's slant is a structural italic trait"
        )
        XCTAssertTrue(TextKitEditorView.structuralInlineTraits(for: .paragraph).isEmpty)
        XCTAssertTrue(TextKitEditorView.structuralInlineTraits(for: .bulletListItem).isEmpty)
        XCTAssertTrue(TextKitEditorView.structuralInlineTraits(for: nil).isEmpty)
    }

    /// The reported bug: caret in a heading must NOT report Bold as an
    /// active inline format — the heading's semibold weight is intrinsic,
    /// not a user-applied Bold mark. (`activeInlineFormats` drives the
    /// accessory bar chips + the Aa popover toggles.)
    func test_activeInlineFormats_inHeading_excludesIntrinsicBold() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Title")]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let textView = UITextView()
        textView.attributedText = flat.attributed
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.typingAttributes = TextKitEditorView.typingAttributes(
            for: .heading(level: 1), blockID: UUID(), groupID: nil,
            bodyFont: bodyFont, bodyColor: bodyColor
        )
        let active = TextKitEditorView.activeInlineFormats(
            in: textView, paragraphIndex: ParagraphIndex(document: doc)
        )
        XCTAssertFalse(active.contains(.bold), "Heading weight must not read as an active Bold mark")
    }

    /// Parse-back must not persist a heading's intrinsic weight as a
    /// `.bold` inline mark — otherwise demoting the heading to body would
    /// leave the text bold.
    func test_documentFromIndex_heading_roundTripsWithoutBoldMarks() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Title")]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc), storage: flat.attributed
        )
        guard case .heading(_, let inline) = recovered.blocks[0].kind else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(inline.map(\.text).joined(), "Title")
        XCTAssertTrue(
            inline.allSatisfy { $0.marks.isEmpty },
            "Heading intrinsic weight must not round-trip as a bold mark"
        )
    }

    /// Same guarantee for a blockquote's intrinsic italic slant.
    func test_documentFromIndex_blockquote_roundTripsWithoutItalicMarks() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quote")]))
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc), storage: flat.attributed
        )
        guard case .blockquote(let children) = recovered.blocks[0].kind,
              case .paragraph(let inline) = children[0].kind else {
            return XCTFail("Expected blockquote → paragraph")
        }
        XCTAssertEqual(inline.map(\.text).joined(), "Quote")
        XCTAssertTrue(
            inline.allSatisfy { $0.marks.isEmpty },
            "Blockquote intrinsic slant must not round-trip as an italic mark"
        )
    }

    /// A user-applied Bold on top of BODY text is still recovered — the
    /// subtraction only removes a kind's STRUCTURAL trait, not explicit
    /// marks. (Guards against over-correcting Fix 1.)
    func test_documentFromIndex_bodyBold_stillRecovered() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "hi", marks: [.bold])]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let recovered = TextKitEditorView.documentFromIndex(
            ParagraphIndex(document: doc), storage: flat.attributed
        )
        guard case .paragraph(let inline) = recovered.blocks[0].kind else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(inline.first?.marks, [.bold], "Explicit bold on body text must survive")
    }
}
#endif
