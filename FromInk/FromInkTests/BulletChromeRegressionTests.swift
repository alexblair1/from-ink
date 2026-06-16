#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit
import XCTest
@testable import FromInk

/// Regression tests for the disappearing-bullet bug.
///
/// **Root cause (verified empirically 2026-06-10):** UIKit re-derives
/// `UITextView.typingAttributes` on EVERY selection change — tap,
/// arrow key, programmatic `selectedRange` set — and the derived
/// dictionary carries ONLY standard attributes. The custom keys
/// (`.paragraphKind`, `.blockID`, `.groupID`, …) were silently dropped,
/// so the first character typed after any caret move landed
/// chromeless: the paragraph probed as a body paragraph, the
/// bullet/number/quote chrome vanished, and parse-back dissolved the
/// list. The fix re-asserts the custom keys in
/// `textViewDidChangeSelection` via
/// `TextKitEditorView.typingAttributesPreservingChrome`.
@MainActor
final class BulletChromeRegressionTests: XCTestCase {

    private let bodyFont = UIFont.systemFont(ofSize: 17)
    private let bodyColor = UIColor.label

    /// Full editor rig: hand-built TextKit 1 stack + a real
    /// Coordinator wired as delegate, exactly like `makeUIView`.
    /// Observable stand-in for the reducer's mirrored state — the rig
    /// asserts what the coordinator pushes through the bindings.
    private final class ReducerMirror {
        var document: RichTextDocument = .empty
        var selection: BlockTreeSelection = BlockTreeSelection()
        var commands: [EditorCommand] = []
    }

    private func makeEditorRig(
        document: RichTextDocument
    ) -> (textView: UITextView, coordinator: TextKitEditorView.Coordinator, mirror: ReducerMirror) {
        let storage = NSTextStorage()
        let layoutManager = BlockDecoratingLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = BlockTreeTextView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480),
            textContainer: container
        )
        textView.font = bodyFont
        textView.textColor = bodyColor
        textView.textContainer.lineFragmentPadding = 0

        let mirror = ReducerMirror()
        mirror.document = document
        let view = TextKitEditorView(
            document: Binding(get: { mirror.document }, set: { mirror.document = $0 }),
            selection: Binding(get: { mirror.selection }, set: { mirror.selection = $0 }),
            onSlashTyped: { _, _, _ in },
            onCommand: { mirror.commands.append($0) },
            onCaretAnchorMoved: { _ in },
            onSlashFilterChanged: { _ in },
            isSlashPaletteOpen: false,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        let coordinator = view.makeCoordinator()
        coordinator.textView = textView
        textView.delegate = coordinator

        let flat = TextKitEditorView.flatten(document: document, bodyFont: bodyFont, bodyColor: bodyColor)
        textView.attributedText = flat.attributed
        coordinator.paragraphIndex = ParagraphIndex(document: document)
        coordinator.lastNewlineCount = TextKitEditorView.newlineCount(in: flat.attributed.string as NSString)

        // Mirror makeUIView's `onEditorCommand` wiring so dispatch
        // tests exercise the real path the accessory bar + keyboard
        // shortcuts ride.
        textView.onEditorCommand = { [weak coordinator] command in
            guard let coord = coordinator else { return }
            switch command {
            case .toggleBold:          coord.applyInlineToggle(.bold);          return
            case .toggleItalic:        coord.applyInlineToggle(.italic);        return
            case .toggleUnderline:     coord.applyInlineToggle(.underline);     return
            case .toggleStrikethrough: coord.applyInlineToggle(.strikethrough); return
            case .toggleCode:          coord.applyInlineToggle(.code);          return
            default:
                break
            }
            mirror.commands.append(command)
        }
        return (textView, coordinator, mirror)
    }

    private func emptyBulletDoc() -> RichTextDocument {
        RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: []))])
            ]))
        ])
    }

    private func paragraphKind(at location: Int, in textView: UITextView) -> ParagraphKind? {
        guard location < textView.attributedText.length else { return nil }
        let attrs = textView.attributedText.attributes(at: location, effectiveRange: nil)
        return (attrs[.paragraphKind] as? Int).flatMap(ParagraphKind.init(attributeValue:))
    }

    /// Mirror the real input-system event sequence for a caret move +
    /// keystroke. Headless programmatic `selectedRange` sets don't
    /// dispatch `textViewDidChangeSelection` (taps and key-driven
    /// moves do on-device), so the rig invokes the delegate methods
    /// in the order UIKit does: selection change → didChangeSelection
    /// → shouldChangeTextIn → insertion.
    private func moveCaretAndType(
        _ text: String,
        at location: Int,
        textView: UITextView,
        coordinator: TextKitEditorView.Coordinator
    ) {
        textView.selectedRange = NSRange(location: location, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        let accepted = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: location, length: 0),
            replacementText: text
        )
        guard accepted else { return }
        textView.insertText(text)
    }

    func test_typingIntoEmptyBulletItem_afterCaretPlacement_keepsBulletChrome() {
        let (textView, coordinator, _) = makeEditorRig(document: emptyBulletDoc())

        // The tap-to-focus path: a selection change makes UIKit strip
        // the custom keys from typingAttributes; the delegate's
        // re-assertion must restore them before the first keystroke.
        moveCaretAndType("a", at: 0, textView: textView, coordinator: coordinator)

        XCTAssertEqual(textView.attributedText.string, "a\n")
        XCTAssertEqual(
            paragraphKind(at: 0, in: textView), .bulletListItem,
            "Typed character must carry the bullet chrome — its absence is the disappearing-bullet bug"
        )
        // `.blockID` was the per-paragraph identity attribute UIKit's
        // `typingAttributes` machinery kept stripping; Chunk 9 removed
        // it in favor of the side-channel `ParagraphIndex`. The bullet-
        // rendering check above is the load-bearing invariant for this
        // bug class.
    }

    func test_typingMidParagraph_afterArrowMove_keepsChromeOfHostParagraph() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "item")]))])
            ]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)

        // Caret move into the middle of the item (the arrow-key /
        // tap-mid-word path), then type.
        moveCaretAndType("X", at: 2, textView: textView, coordinator: coordinator)

        XCTAssertEqual(textView.attributedText.string, "itXem\n")
        for location in 0..<5 {
            XCTAssertEqual(
                paragraphKind(at: location, in: textView), .bulletListItem,
                "Char at \(location) lost bullet chrome after mid-paragraph typing"
            )
        }
    }

    func test_documentBuild_afterTypingIntoEmptyBulletItem_preservesListStructure() {
        let (textView, coordinator, _) = makeEditorRig(document: emptyBulletDoc())
        moveCaretAndType("a", at: 0, textView: textView, coordinator: coordinator)

        let parsed = TextKitEditorView.documentFromIndex(
            coordinator.paragraphIndex,
            storage: textView.attributedText
        )
        guard case .bulletList(let items) = parsed.blocks.first?.kind else {
            XCTFail("List dissolved to \(String(describing: parsed.blocks.first?.kind)) — the downstream symptom of chromeless typing")
            return
        }
        XCTAssertEqual(items.count, 1)
        guard case .paragraph(let inline) = items.first?.content.first?.kind else {
            XCTFail("Expected paragraph row inside the list")
            return
        }
        XCTAssertEqual(inline.first?.text, "a")
    }

    func test_enterOnBulletItem_caretStaysOnNewLine_reducerMirrorAgrees() {
        // The caret-jumps-to-previous-line bug: after Enter, identity
        // hygiene reassigns the new line a fresh blockID WITHOUT a
        // selection change, so the reducer's mirrored selection still
        // named the OLD block. updateUIView's semantic gate then
        // "corrected" the caret back to the previous bullet line.
        // The sync must re-mirror the bridged selection so reducer
        // state and storage identity agree.
        let originalLeafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(id: originalLeafID, kind: .paragraph(inline: [Inline(text: "abc")]))])
            ]))
        ])
        let (textView, coordinator, mirror) = makeEditorRig(document: doc)

        // Return at the end of "abc": event sequence as on-device —
        // selection settle, shouldChange (returns true: native Enter),
        // insertion, then the (next-runloop on device) didChange.
        moveCaretAndType("\n", at: 3, textView: textView, coordinator: coordinator)
        coordinator.textViewDidChangeSelection(textView)
        coordinator.textViewDidChange(textView)

        // Caret is on the new (second) line.
        XCTAssertEqual(textView.selectedRange, NSRange(location: 4, length: 0))
        XCTAssertEqual(textView.attributedText.string, "abc\n\n")
        XCTAssertEqual(paragraphKind(at: 4, in: textView), .bulletListItem, "New line keeps the bullet chrome")

        // The reducer's mirrored selection must agree with the
        // storage's post-hygiene identity (fresh second-item id, NOT
        // the original leaf) — disagreement is what yanked the caret.
        let bridged = TextKitEditorView.bridgeSelection(
            storage: textView.attributedText,
            selectedRange: textView.selectedRange,
            paragraphIndex: coordinator.paragraphIndex
        )
        XCTAssertEqual(mirror.selection, bridged, "Sync must re-mirror the bridged selection")
        XCTAssertNotEqual(mirror.selection.path.last, originalLeafID, "Selection names the NEW line's fresh id")

        // And updateUIView's re-sync would be a no-op: the reducer
        // selection maps back to exactly the textView's current caret.
        let nsRange = TextKitEditorView.nsRange(
            for: mirror.selection,
            paragraphIndex: coordinator.paragraphIndex,
            totalLength: textView.attributedText.length
        )
        XCTAssertEqual(nsRange, textView.selectedRange, "Reducer selection round-trips to the current caret — no jump")

        // Document mirror has two list items, original id on the first.
        guard case .bulletList(let items) = mirror.document.blocks.first?.kind else {
            XCTFail("Expected bullet list in the mirrored document")
            return
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.content.first?.id, originalLeafID, "First half keeps the original leaf id")
    }

    func test_enterOnEmptySingleBulletItem_emitsExitList_andSuppressesNewline() {
        let (textView, coordinator, mirror) = makeEditorRig(document: emptyBulletDoc())

        textView.selectedRange = NSRange(location: 0, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        let accepted = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(accepted, "Enter on an empty list item must be suppressed — the exit goes through the reducer")
        XCTAssertEqual(mirror.commands, [.exitList])
        // The pre-command sync must leave reducer doc + selection
        // consistent so the reducer's exitList surgery resolves.
        XCTAssertEqual(mirror.selection.path.count, 2, "Bridged selection addresses [container, leaf]")
        XCTAssertEqual(mirror.selection.path.last, mirror.document.blocks.first?.descendants.first?.id)
    }

    func test_enterOnEmptyLastItemOfMultiItemList_emitsExitList() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "a")]))]),
                ListItem(content: [Block(kind: .paragraph(inline: []))])
            ]))
        ])
        let (textView, coordinator, mirror) = makeEditorRig(document: doc)

        // Caret on the empty second item ("a\n" + empty item's \n at 2).
        textView.selectedRange = NSRange(location: 2, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        let accepted = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 2, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(mirror.commands, [.exitList])
        // The reducer can only exit when the selection resolves to a
        // [container, leaf] path AND that leaf exists in the mirrored
        // document — a 1-element fallback path means parse-back and
        // storage disagree on the empty item's id (the swallowed-
        // Return bug).
        XCTAssertEqual(mirror.selection.path.count, 2, "Bridged selection must address [container, leaf]")
        let leaf = mirror.document.block(at: mirror.selection.path)
        XCTAssertEqual(leaf?.joinedInlineText, "", "Selection must resolve to the empty item in the mirrored document")
    }

    func test_deleteEverything_resetsTypingAttributesToBody() {
        // Symptom: create a list, select-all, delete — the caret keeps
        // the list indentation (stale paragraphStyle + chrome in
        // typingAttributes), and the next typed character resurrects
        // list styling in an empty document.
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "item")]))])
            ]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)

        // Select-all + delete, through the real event sequence.
        let fullRange = NSRange(location: 0, length: textView.attributedText.length)
        textView.selectedRange = fullRange
        coordinator.textViewDidChangeSelection(textView)
        let accepted = coordinator.textView(
            textView, shouldChangeTextIn: fullRange, replacementText: ""
        )
        XCTAssertTrue(accepted)
        textView.deleteBackward()
        coordinator.textViewDidChangeSelection(textView)
        coordinator.textViewDidChange(textView)

        XCTAssertEqual(textView.attributedText.length, 0)
        let typing = textView.typingAttributes
        let kind = (typing[.paragraphKind] as? Int).flatMap(ParagraphKind.init(attributeValue:))
        XCTAssertNotEqual(kind, .bulletListItem, "Empty document must not keep list kind in typing attributes")
        let style = typing[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent ?? 0, 0, "List indentation must not survive into an empty document")
        XCTAssertEqual(style?.firstLineHeadIndent ?? 0, 0)
    }

    func test_typingAttributesPreservingChrome_keepsDerivedStandardAttributes() {
        let doc = emptyBulletDoc()
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let boldFont = UIFont.boldSystemFont(ofSize: 17)
        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: [.font: boldFont],
            storage: flat.attributed,
            caretLocation: 0,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        XCTAssertEqual(
            merged[.font] as? UIFont, boldFont,
            "UIKit's derived standard attributes (inline continuation) must survive the merge"
        )
        XCTAssertEqual(
            (merged[.paragraphKind] as? Int).flatMap(ParagraphKind.init(attributeValue:)),
            .bulletListItem,
            "Custom paragraphKind re-asserted from the paragraph probe"
        )
    }

    func test_typingAttributesPreservingChrome_emptyStorage_resetsToBodyParagraph() {
        // Stale list attrs after delete-everything must reset, not
        // pass through — otherwise the caret keeps the list indent
        // and the next character resurrects the list.
        let staleListStyle = NSMutableParagraphStyle()
        staleListStyle.headIndent = 28
        staleListStyle.firstLineHeadIndent = 28
        let derived: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .paragraphStyle: staleListStyle,
            .paragraphKind: ParagraphKind.bulletListItem.attributeValue
        ]
        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: derived,
            storage: NSAttributedString(),
            caretLocation: 0,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        XCTAssertEqual(
            (merged[.paragraphKind] as? Int).flatMap(ParagraphKind.init(attributeValue:)),
            .paragraph,
            "Empty storage resets to body-paragraph typing attributes"
        )
        let style = merged[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent ?? -1, 0)
        XCTAssertEqual(style?.firstLineHeadIndent ?? -1, 0)
    }

    /// Fast double-Return: iOS 26 defers `textViewDidChange` to the
    /// next runloop, so a quick second Return arrives BEFORE the
    /// first Return's didChange (and therefore before identity
    /// hygiene + sync). The exit-list branch must settle hygiene
    /// itself or the bridge resolves the caret against duplicate
    /// blockIDs — exiting the WRONG (non-empty, first) item.
    func test_fastDoubleReturn_exitsTheEmptySecondItem_notTheFirst() {
        let firstLeafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(id: firstLeafID, kind: .paragraph(inline: [Inline(text: "x")]))])
            ]))
        ])
        let (textView, coordinator, mirror) = makeEditorRig(document: doc)

        // Return #1 at the end of "x" — native insert. NO didChange
        // yet (deferred on device).
        textView.selectedRange = NSRange(location: 1, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        XCTAssertTrue(coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 1, length: 0),
            replacementText: "\n"
        ))
        textView.insertText("\n")
        coordinator.textViewDidChangeSelection(textView)

        // Return #2 lands while the storage still carries the
        // duplicate blockID on the new empty paragraph.
        let accepted = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 2, length: 0),
            replacementText: "\n"
        )

        XCTAssertFalse(accepted, "Second Return on the empty item must route to exitList")
        XCTAssertEqual(mirror.commands, [.exitList])
        // The mirrored selection must name the EMPTY second item —
        // naming the first ("x") makes the reducer wipe its text.
        XCTAssertEqual(mirror.selection.path.count, 2)
        XCTAssertNotEqual(
            mirror.selection.path.last, firstLeafID,
            "Bridge resolved the caret to the FIRST item — stale hygiene at sync time"
        )
        // And the named leaf must actually be empty in the mirrored doc.
        let leaf = mirror.document.block(at: mirror.selection.path)
        XCTAssertEqual(leaf?.joinedInlineText, "", "exitList must target the empty item")
    }

    // MARK: - Phantom tail position

    func test_shouldExitList_atPhantomPositionAfterFinalNewline_returnsFalse() {
        // Caret past the document's final \n addresses NO paragraph.
        // The probe must not fall back to the PREVIOUS paragraph's
        // list chrome — that fired exitList against an unset
        // selection (reducer no-op) while suppressing the newline:
        // Return appeared completely dead.
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "x")]))])
            ]))
        ])
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        XCTAssertFalse(TextKitEditorView.shouldExitList(
            replacementText: "\n",
            replacementRange: NSRange(location: flat.attributed.length, length: 0),
            storage: flat.attributed,
            paragraphIndex: ParagraphIndex(document: doc)
        ))
    }

    func test_caretClamp_snapsPhantomPositionToEndOfLastParagraph() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "x")]))])
            ]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)

        // Tap below the last line → UIKit parks the caret at the
        // phantom extra-line-fragment position (== storage length).
        textView.selectedRange = NSRange(location: textView.attributedText.length, length: 0)
        coordinator.textViewDidChangeSelection(textView)

        XCTAssertEqual(
            textView.selectedRange,
            NSRange(location: textView.attributedText.length - 1, length: 0),
            "Caret must snap off the phantom position to the end of the last real paragraph"
        )
    }

    // MARK: - Inline toggles (Bold / Italic / Underline / Strikethrough)

    /// Selecting a word and calling Bold applies `.traitBold` to that
    /// word's font in storage. Pin every guard inside `applyInlineToggle`
    /// — if any one of `.paragraphKind`, `.blockID`, paragraphSlice's
    /// probe location, or the selection-length check regresses, this
    /// test catches the silent no-op.
    func test_applyInlineToggle_bold_appliesBoldTraitToSelection() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)

        // Select "Hello".
        textView.selectedRange = NSRange(location: 0, length: 5)
        coordinator.applyInlineToggle(.bold)

        let font = textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(
            font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
            "Bold trait must land on the selected run"
        )
    }

    func test_applyInlineToggle_italic_appliesItalicTraitToSelection() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 0, length: 5)
        coordinator.applyInlineToggle(.italic)

        let font = textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    func test_applyInlineToggle_underline_setsUnderlineStyle() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 0, length: 5)
        coordinator.applyInlineToggle(.underline)

        let style = textView.attributedText.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue, "Underline style must land on the selected run")
    }

    func test_applyInlineToggle_strikethrough_setsStrikethroughStyle() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 0, length: 5)
        coordinator.applyInlineToggle(.strikethrough)

        let style = textView.attributedText.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue, "Strikethrough style must land on the selected run")
    }

    /// Full dispatch chain: BlockTreeTextView's `onEditorCommand`
    /// closure (set in makeUIView) routes inline toggles to the
    /// Coordinator's `applyInlineToggle`. This pins the wiring the
    /// accessory bar buttons and keyboard shortcuts both ride.
    func test_onEditorCommand_toggleBold_appliesBoldToSelection() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        // Hold the coordinator strongly — SwiftUI's representable
        // context does this in production; in a test rig the only
        // strong refs are what we choose to keep.
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        _ = coordinator
        guard let blockTreeTextView = textView as? BlockTreeTextView else {
            return XCTFail("Test rig must use BlockTreeTextView")
        }
        textView.selectedRange = NSRange(location: 0, length: 5)
        blockTreeTextView.onEditorCommand?(.toggleBold)

        let font = textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(
            font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
            "Bold must land via the full onEditorCommand → applyInlineToggle dispatch"
        )
    }

    // MARK: - Caret-only toggle (Apple Notes / Notion convention)

    /// Tapping Bold with no selection flips `typingAttributes` so the
    /// NEXT character typed is bold. Matches the convention every major
    /// note app uses; before this, the toggle silently no-op'd on a
    /// caret-only selection — the reported B/I/U/S regression.
    func test_applyInlineToggle_bold_noSelection_flipsTypingAttributes() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)  // caret at end of "Hello"
        coordinator.applyInlineToggle(.bold)

        let font = textView.typingAttributes[.font] as? UIFont
        XCTAssertTrue(
            font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
            "Caret-only Bold must flip typingAttributes so the next typed char is bold"
        )
    }

    func test_applyInlineToggle_italic_noSelection_flipsTypingAttributes() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.italic)

        let font = textView.typingAttributes[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    func test_applyInlineToggle_underline_noSelection_setsUnderlineStyle() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.underline)

        let style = textView.typingAttributes[.underlineStyle] as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func test_applyInlineToggle_strikethrough_noSelection_setsStrikethroughStyle() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.strikethrough)

        let style = textView.typingAttributes[.strikethroughStyle] as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    /// Combined marks — Bold + Italic stacks correctly on the
    /// typingAttributes font (Bold Italic). User should be able to
    /// write in any permutation.
    func test_applyInlineToggle_boldThenItalic_noSelection_combinesBoth() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.bold)
        coordinator.applyInlineToggle(.italic)

        let font = textView.typingAttributes[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    /// Underline stacks orthogonally with bold/italic.
    func test_applyInlineToggle_boldAndUnderline_noSelection_combinesBoth() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.bold)
        coordinator.applyInlineToggle(.underline)

        let font = textView.typingAttributes[.font] as? UIFont
        let underline = textView.typingAttributes[.underlineStyle] as? Int
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue)
    }

    // MARK: - Active block-kind probe (drives the list / heading chips)

    /// Caret inside a bullet-list item → kind reads as `.bulletListItem`.
    /// Drives the bulleted button's filled state on the accessory bar.
    func test_activeParagraphKind_insideBulletList_isBulletListItem() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "row")]))])
            ]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 1, length: 0)  // inside "row"

        XCTAssertEqual(
            TextKitEditorView.activeParagraphKind(in: textView, paragraphIndex: coordinator.paragraphIndex),
            .bulletListItem
        )
    }

    /// Same for ordered lists.
    func test_activeParagraphKind_insideOrderedList_isOrderedListItem() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "row")]))])
            ]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 1, length: 0)

        XCTAssertEqual(
            TextKitEditorView.activeParagraphKind(in: textView, paragraphIndex: coordinator.paragraphIndex),
            .orderedListItem
        )
    }

    /// Caret in a top-level body paragraph → no list kind. The
    /// accessory bar's list buttons stay un-filled.
    func test_activeParagraphKind_inBodyParagraph_isParagraph() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 2, length: 0)

        XCTAssertEqual(
            TextKitEditorView.activeParagraphKind(in: textView, paragraphIndex: coordinator.paragraphIndex),
            .paragraph
        )
    }

    /// Caret in a heading → kind carries the level.
    func test_activeParagraphKind_inHeading_carriesLevel() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 2, inline: [Inline(text: "Title")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 0, length: 0)

        XCTAssertEqual(
            TextKitEditorView.activeParagraphKind(in: textView, paragraphIndex: coordinator.paragraphIndex),
            .heading(level: 2)
        )
    }

    // MARK: - Active-state probe (drives the accessory bar's chips)

    /// Empty typingAttributes → no marks active.
    func test_activeInlineFormats_initialState_isEmpty() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, _, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)

        XCTAssertTrue(TextKitEditorView.activeInlineFormats(in: textView).isEmpty)
    }

    /// After flipping Bold at the caret, the active set contains .bold.
    func test_activeInlineFormats_afterBoldToggle_containsBold() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.bold)

        XCTAssertEqual(TextKitEditorView.activeInlineFormats(in: textView), [.bold])
    }

    /// Multiple marks stacked → all show as active.
    func test_activeInlineFormats_boldAndItalic_bothActive() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.bold)
        coordinator.applyInlineToggle(.italic)

        let active = TextKitEditorView.activeInlineFormats(in: textView)
        XCTAssertTrue(active.contains(.bold))
        XCTAssertTrue(active.contains(.italic))
    }

    /// Underline + strikethrough probe.
    func test_activeInlineFormats_underlineAndStrikethrough_bothActive() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.underline)
        coordinator.applyInlineToggle(.strikethrough)

        let active = TextKitEditorView.activeInlineFormats(in: textView)
        XCTAssertTrue(active.contains(.underline))
        XCTAssertTrue(active.contains(.strikethrough))
    }

    /// Toggling the same mark twice with no selection returns
    /// typingAttributes to the un-marked state.
    func test_applyInlineToggle_bold_twice_noSelection_returnsToUnbold() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.applyInlineToggle(.bold)
        coordinator.applyInlineToggle(.bold)

        let font = textView.typingAttributes[.font] as? UIFont
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    /// The system editing menu fires `formatBold(_:)` (etc) on the
    /// text view. Verify the @objc bridge routes to onEditorCommand.
    func test_formatBoldSelector_routesToOnEditorCommand() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Hello world")]))
        ])
        let (textView, coordinator, _) = makeEditorRig(document: doc)
        _ = coordinator
        guard let blockTreeTextView = textView as? BlockTreeTextView else {
            return XCTFail("Test rig must use BlockTreeTextView")
        }
        textView.selectedRange = NSRange(location: 0, length: 5)
        blockTreeTextView.formatBold(nil)  // simulates Cmd+B keyCommand action

        let font = textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(
            font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
            "formatBold(_:) selector must apply bold via onEditorCommand"
        )
    }
}
#endif
