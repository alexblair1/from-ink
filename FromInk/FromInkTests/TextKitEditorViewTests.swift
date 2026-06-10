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
        XCTAssertEqual(attrs[.blockChrome] as? Int, BlockChrome.blockquoteParagraph.rawValue)
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
            flattenIDMap: flattened.flattenIDMap,
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

    // MARK: - B1 — parse-back dedupes colliding block IDs

    func test_parseBack_duplicateBlockIDs_areDeduped() {
        // Build an NSAttributedString manually with TWO paragraphs
        // carrying the same .blockID — the shape UITextView produces
        // after Enter (the new paragraph inherits the prior one's
        // typingAttributes including blockID).
        let sharedID = UUID()
        let mutable = NSMutableAttributedString()

        let paraAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label,
            .blockChrome: BlockChrome.paragraph.rawValue,
            .blockID: sharedID
        ]
        mutable.append(NSAttributedString(string: "First", attributes: paraAttrs))
        mutable.append(NSAttributedString(string: "\n", attributes: paraAttrs))
        mutable.append(NSAttributedString(string: "Second", attributes: paraAttrs))

        let recovered = TextKitEditorView.parseBack(mutable)
        XCTAssertEqual(recovered.blocks.count, 2)
        XCTAssertNotEqual(
            recovered.blocks[0].id,
            recovered.blocks[1].id,
            "Duplicate block IDs must be de-duplicated — the second paragraph gets a fresh UUID"
        )
        // The first paragraph keeps the original id.
        XCTAssertEqual(recovered.blocks[0].id, sharedID)
    }

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
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
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
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
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
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
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
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
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
        let recovered = TextKitEditorView.parseBack(flattened.attributed)
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
        let flattened = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        // Selection from offset 2 through 9 ("rst\nSec") — spans paragraphs.
        let nsRange = NSRange(location: 2, length: 7)
        let bridged = TextKitEditorView.selection(
            forNSRange: nsRange,
            flattenMap: flattened.flattenMap
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
            flattenIDMap: flattened.flattenIDMap,
            totalLength: flattened.attributed.length
        )
        XCTAssertNotNil(nsRange)
        XCTAssertEqual(nsRange?.location, 5, "Start clamps to leaf's text length")
        XCTAssertEqual(nsRange?.length, 0, "End clamps to leaf's text length too")
    }
}
#endif
