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
/// (`.blockChrome`, `.blockID`, `.groupID`, …) were silently dropped,
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
    private func makeEditorRig(
        document: RichTextDocument
    ) -> (textView: UITextView, coordinator: TextKitEditorView.Coordinator) {
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

        let view = TextKitEditorView(
            document: .constant(document),
            selection: .constant(BlockTreeSelection()),
            onSlashTyped: { _, _, _ in },
            onCommand: { _ in },
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
        return (textView, coordinator)
    }

    private func emptyBulletDoc() -> RichTextDocument {
        RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: []))])
            ]))
        ])
    }

    private func chrome(at location: Int, in textView: UITextView) -> BlockChrome? {
        guard location < textView.attributedText.length else { return nil }
        let attrs = textView.attributedText.attributes(at: location, effectiveRange: nil)
        return (attrs[.blockChrome] as? Int).flatMap(BlockChrome.init(rawValue:))
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
        let (textView, coordinator) = makeEditorRig(document: emptyBulletDoc())

        // The tap-to-focus path: a selection change makes UIKit strip
        // the custom keys from typingAttributes; the delegate's
        // re-assertion must restore them before the first keystroke.
        moveCaretAndType("a", at: 0, textView: textView, coordinator: coordinator)

        XCTAssertEqual(textView.attributedText.string, "a\n")
        XCTAssertEqual(
            chrome(at: 0, in: textView), .bulletListItem,
            "Typed character must carry the bullet chrome — its absence is the disappearing-bullet bug"
        )
        XCTAssertNotNil(
            textView.attributedText.attribute(.blockID, at: 0, effectiveRange: nil),
            "Typed character must carry the paragraph's blockID for selection bridging + parse-back"
        )
    }

    func test_typingMidParagraph_afterArrowMove_keepsChromeOfHostParagraph() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [Block(kind: .paragraph(inline: [Inline(text: "item")]))])
            ]))
        ])
        let (textView, coordinator) = makeEditorRig(document: doc)

        // Caret move into the middle of the item (the arrow-key /
        // tap-mid-word path), then type.
        moveCaretAndType("X", at: 2, textView: textView, coordinator: coordinator)

        XCTAssertEqual(textView.attributedText.string, "itXem\n")
        for location in 0..<5 {
            XCTAssertEqual(
                chrome(at: location, in: textView), .bulletListItem,
                "Char at \(location) lost bullet chrome after mid-paragraph typing"
            )
        }
    }

    func test_parseBack_afterTypingIntoEmptyBulletItem_preservesListStructure() {
        let (textView, coordinator) = makeEditorRig(document: emptyBulletDoc())
        moveCaretAndType("a", at: 0, textView: textView, coordinator: coordinator)

        let parsed = TextKitEditorView.parseBack(textView.attributedText)
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

    func test_typingAttributesPreservingChrome_keepsDerivedStandardAttributes() {
        let doc = emptyBulletDoc()
        let flat = TextKitEditorView.flatten(document: doc, bodyFont: bodyFont, bodyColor: bodyColor)
        let boldFont = UIFont.boldSystemFont(ofSize: 17)
        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: [.font: boldFont],
            storage: flat.attributed,
            caretLocation: 0
        )
        XCTAssertEqual(
            merged[.font] as? UIFont, boldFont,
            "UIKit's derived standard attributes (inline continuation) must survive the merge"
        )
        XCTAssertEqual(
            (merged[.blockChrome] as? Int).flatMap(BlockChrome.init(rawValue:)),
            .bulletListItem,
            "Custom chrome key re-asserted from the paragraph probe"
        )
    }

    func test_typingAttributesPreservingChrome_emptyStorage_passesThroughDerived() {
        let derived: [NSAttributedString.Key: Any] = [.font: bodyFont]
        let merged = TextKitEditorView.typingAttributesPreservingChrome(
            derived: derived,
            storage: NSAttributedString(),
            caretLocation: 0
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[.blockChrome])
    }
}
#endif
