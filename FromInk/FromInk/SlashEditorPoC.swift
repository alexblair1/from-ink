#if os(iOS) || os(visionOS)
import Combine
import SwiftUI
import UIKit

// MARK: - SlashEditorPoC
//
// Throwaway proof-of-concept editor used to validate the architectural
// hypothesis: TextKit 1 with a custom NSLayoutManager + per-paragraph
// blockType attribute can render block-level structure (headings,
// blockquote bar, lists, dividers, code) in an editable UITextView.
//
// The production editor uses TCA + AttributedString + PresentationIntent.
// This file uses none of that — it's a self-contained UIViewRepresentable
// to keep variables-changed minimal between the PoC and the final
// architecture. Delete this whole file once the architecture is proven
// and the real refactor lands.

enum PoCBlockType: Int {
    case body
    case h1
    case h2
    case quote
}

extension NSAttributedString.Key {
    /// Custom per-paragraph tag the layout manager reads to decide
    /// whether to draw the blockquote bar / tint. Unique to the PoC
    /// to avoid colliding with the production scope.
    static let pocBlockType = NSAttributedString.Key("app.poc.blockType")
}

enum PoCStyle {
    static let body  = UIFont.preferredFont(forTextStyle: .body)
    static let h1    = UIFont.systemFont(ofSize: 28, weight: .bold)
    static let h2    = UIFont.systemFont(ofSize: 22, weight: .semibold)
    static let quote = UIFont.italicSystemFont(ofSize: 17)

    static let quoteIndent: CGFloat   = 24
    static let quoteBarX: CGFloat     = 8
    static let quoteBarWidth: CGFloat = 3

    static let textColor       = UIColor.label
    static let quoteColor      = UIColor.secondaryLabel
    static let quoteBarColor   = UIColor.systemGray2
    static let quoteBackground = UIColor.systemGray6
}

/// **The load-bearing piece.** `drawBackground(forGlyphRange:at:)` only
/// runs in TextKit 1. iOS 16+ UITextView uses TextKit 2 by default and
/// these overrides never fire — which is why every styling attempt on
/// top of `UITextView(usingTextLayoutManager: true)` rendered as plain
/// prose. The PoC proves that explicitly hand-building the TextKit 1
/// stack (NSTextStorage → this NSLayoutManager → NSTextContainer →
/// UITextView(frame:textContainer:)) puts the override back in play.
final class PoCBlockDecoratingLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage = textStorage else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.pocBlockType, in: charRange, options: []) { value, range, _ in
            guard
                let raw = value as? Int,
                let type = PoCBlockType(rawValue: raw),
                type == .quote
            else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, container, _, _ in
                let inset = container.lineFragmentPadding
                let frag = usedRect.offsetBy(dx: origin.x, dy: origin.y)

                let bg = CGRect(x: origin.x + inset,
                                y: frag.minY,
                                width: container.size.width - inset * 2,
                                height: frag.height)
                PoCStyle.quoteBackground.setFill()
                UIBezierPath(rect: bg).fill()

                let bar = CGRect(x: origin.x + PoCStyle.quoteBarX,
                                 y: frag.minY,
                                 width: PoCStyle.quoteBarWidth,
                                 height: frag.height)
                PoCStyle.quoteBarColor.setFill()
                UIBezierPath(rect: bar).fill()
            }
        }
    }
}

@MainActor
final class PoCEditorController: ObservableObject {

    weak var textView: UITextView?

    @Published var isSlashMenuVisible = false
    @Published var slashMenuAnchor: CGRect = .zero

    private var slashStart: Int?

    func apply(_ type: PoCBlockType) {
        dismissSlashMenu(consumingTrigger: true)
        guard let tv = textView else { return }
        let storage = tv.textStorage

        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: tv.selectedRange)

        let attrs = attributes(for: type)

        storage.beginEditing()
        storage.setAttributes(attrs, range: paragraph)
        storage.addAttribute(.pocBlockType, value: type.rawValue, range: paragraph)
        storage.endEditing()

        // Without this, the user's NEXT character reverts to default
        // styling because UITextView uses typingAttributes for inserted
        // text. This is the "next-character-reverts" bug the PoC's
        // comment flagged as critical.
        var typing = attrs
        typing[.pocBlockType] = type.rawValue
        tv.typingAttributes = typing

        tv.setNeedsDisplay()
        tv.delegate?.textViewDidChange?(tv)
    }

    fileprivate func attributes(for type: PoCBlockType) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6

        switch type {
        case .body, .h1, .h2:
            para.firstLineHeadIndent = 0
            para.headIndent = 0
            para.tailIndent = 0
        case .quote:
            para.firstLineHeadIndent = PoCStyle.quoteIndent
            para.headIndent = PoCStyle.quoteIndent
            para.tailIndent = -8
        }

        switch type {
        case .body:
            return [.font: PoCStyle.body, .foregroundColor: PoCStyle.textColor, .paragraphStyle: para]
        case .h1:
            return [.font: PoCStyle.h1, .foregroundColor: PoCStyle.textColor, .paragraphStyle: para]
        case .h2:
            return [.font: PoCStyle.h2, .foregroundColor: PoCStyle.textColor, .paragraphStyle: para]
        case .quote:
            return [.font: PoCStyle.quote, .foregroundColor: PoCStyle.quoteColor, .paragraphStyle: para]
        }
    }

    func slashTyped(at location: Int) {
        slashStart = location
        if let tv = textView, let sel = tv.selectedTextRange {
            slashMenuAnchor = tv.caretRect(for: sel.end)
        }
        isSlashMenuVisible = true
    }

    func dismissSlashMenu(consumingTrigger: Bool) {
        if consumingTrigger, let tv = textView, let start = slashStart {
            let storage = tv.textStorage
            let caret = tv.selectedRange.location
            let remove = NSRange(location: start, length: max(0, caret - start))
            if remove.length > 0 {
                storage.deleteCharacters(in: remove)
                tv.selectedRange = NSRange(location: start, length: 0)
            }
        }
        slashStart = nil
        isSlashMenuVisible = false
    }
}

struct PoCRichTextEditor: UIViewRepresentable {
    @ObservedObject var controller: PoCEditorController

    func makeUIView(context: Context) -> UITextView {
        // Hand-built TextKit 1 stack — DO NOT use
        // UITextView(usingTextLayoutManager: true). The custom layout
        // manager's drawBackground override never runs under TextKit 2.
        let storage = NSTextStorage()
        let layoutManager = PoCBlockDecoratingLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = UITextView(frame: .zero, textContainer: container)
        textView.font = PoCStyle.body
        textView.backgroundColor = .clear
        let typing: [NSAttributedString.Key: Any] = [
            .font: PoCStyle.body,
            .foregroundColor: PoCStyle.textColor,
            .pocBlockType: PoCBlockType.body.rawValue
        ]
        textView.typingAttributes = typing
        textView.delegate = context.coordinator

        controller.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: PoCEditorController
        init(controller: PoCEditorController) { self.controller = controller }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "/" {
                let ns = textView.text as NSString
                let atBoundary = range.location == 0
                    || ["\n", " "].contains(ns.substring(with: NSRange(location: range.location - 1, length: 1)))
                if atBoundary {
                    let slashLocation = range.location
                    DispatchQueue.main.async { self.controller.slashTyped(at: slashLocation) }
                }
            } else if (text == " " || text == "\n"), controller.isSlashMenuVisible {
                DispatchQueue.main.async { self.controller.dismissSlashMenu(consumingTrigger: false) }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {}
    }
}

struct SlashEditorPoCView: View {
    @StateObject private var controller = PoCEditorController()
    @Environment(\.dismiss) private var dismiss

    private let commands: [(title: String, icon: String, type: PoCBlockType)] = [
        ("Text", "textformat", .body),
        ("Heading 1", "textformat.size.larger", .h1),
        ("Heading 2", "textformat.size", .h2),
        ("Quote", "text.quote", .quote),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Slash Editor PoC")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()

            ZStack(alignment: .topLeading) {
                PoCRichTextEditor(controller: controller)
                    .padding(8)

                if controller.isSlashMenuVisible {
                    slashMenu
                        .offset(x: controller.slashMenuAnchor.minX + 8,
                                y: controller.slashMenuAnchor.maxY + 12)
                }
            }
        }
    }

    private var slashMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands, id: \.title) { cmd in
                Button {
                    controller.apply(cmd.type)
                } label: {
                    HStack {
                        Image(systemName: cmd.icon).frame(width: 24)
                        Text(cmd.title)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 220)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }
}
#endif
