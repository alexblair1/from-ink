#if os(iOS) || os(visionOS)
import Combine
import SwiftUI
import UIKit

/// TextKit 1-backed rich text editor for `RichTextDocument`.
///
/// **Why TextKit 1.** SwiftUI's `TextEditor` and
/// `UITextView(usingTextLayoutManager: true)` (TextKit 2) honor
/// inline attributes (bold / italic / etc.) but DO NOT paint
/// block-level structure (headings, lists, blockquote, code blocks,
/// dividers). Manual testing on 2026-06-09 confirmed both paths
/// silently render block-level intents as plain prose.
///
/// The PoC verified that hand-building the TextKit 1 stack
/// (`NSTextStorage` → custom `NSLayoutManager` subclass →
/// `NSTextContainer` → `UITextView(frame:textContainer:)`) lets us
/// override `drawBackground(forGlyphRange:at:)`, which is the ONLY
/// API for drawing block-level chrome inside an editable text view
/// on iOS. iOS 16+'s default UITextView uses TextKit 2 where the
/// override never fires.
///
/// **Document model.** Content is a `RichTextDocument` (block tree
/// per `text_experience_edd.md` §5.3). The view flattens the document
/// to an `NSAttributedString` for layout, decorating each paragraph
/// with custom attributes the `BlockDecoratingLayoutManager` reads in
/// `drawBackground`. On user edits, the coordinator parses the
/// updated `NSAttributedString` back into a `RichTextDocument` and
/// pushes it to the reducer via `onDocumentEdited`.
///
/// **Flatten format.** One paragraph per leaf block:
///
///   - Each paragraph carries `.blockChrome` (an `Int` rawValue of
///     `BlockChrome`) — the layout manager's discriminator for
///     drawing chrome.
///   - Each paragraph carries `.blockID` (the `UUID` of the source
///     leaf) — the parse-back path needs this to preserve block IDs
///     where possible.
///   - List items and blockquote children carry `.groupID` (shared
///     across all paragraphs in the same container) so the parse-back
///     can re-group them into a single `bulletList` / `orderedList` /
///     `blockquote` container.
///   - Divider paragraphs contain a non-breaking space as a glyph
///     anchor; the layout manager draws the actual rule.
///
/// **Caveat — ID stability across parse-back.** v1 parse-back assigns
/// fresh UUIDs to paragraphs whose `.blockID` attribute is missing
/// (e.g. a brand-new paragraph from pressing Enter) and re-uses the
/// stored id where present. NoteRegion text-range anchors (Phase 6)
/// will need a more careful approach — a Coordinator-level "structural
/// edit" stream that emits explicit split/merge events rather than
/// inferring from parse-back. Logged TODO; acceptable for v1 because
/// NoteRegion text anchors aren't shipped yet.
@MainActor
struct TextKitEditorView: UIViewRepresentable {
    @Binding var document: RichTextDocument
    @Binding var selection: BlockTreeSelection
    /// Fired when the user types a `/` at a paragraph boundary. The
    /// `caretRect` is the rect of the `/` glyph in the editor
    /// `UITextView`'s **viewport** coordinate space (post
    /// `contentOffset` subtraction) — used by the wiring view as the
    /// `.popover()` attachment anchor so the palette appears beside
    /// the slash regardless of how far the document has scrolled.
    let onSlashTyped: (_ blockPath: [UUID], _ offsetUTF16: Int, _ caretRect: CGRect) -> Void
    /// Routed from the custom UITextView subclass's `keyCommands` to
    /// the wiring view, which maps each `EditorCommand` onto a TCA
    /// action. The editor view stays feature-agnostic — it doesn't
    /// know about `TextEditingFeature.Action` names.
    let onCommand: (EditorCommand) -> Void
    /// Republishes the caret rect of the pinned slash position while
    /// the palette is open and the user scrolls the editor. The
    /// wiring view stores the rect in `@State` so the popover
    /// anchor tracks the slash glyph through scroll. Only fires
    /// while `isSlashPaletteOpen` is true.
    let onCaretAnchorMoved: (CGRect) -> Void
    /// Live filter text while the palette is open, computed
    /// STORAGE-side per keystroke (the document mirror is debounced
    /// under the imperative boundary — EDD §22.4.1 — so it can't
    /// drive realtime filtering). `nil` means the trigger `/` is gone
    /// — the wiring dismisses the palette. The reducer's document-
    /// based refresh still runs on each documentEdited and converges
    /// to the same value.
    let onSlashFilterChanged: (String?) -> Void
    /// True while the slash palette is presented. Tells the
    /// `Coordinator` to clear its pinned slash location when the
    /// palette closes (so scroll events stop emitting stale anchor
    /// updates).
    let isSlashPaletteOpen: Bool
    let bodyFont: UIFont
    let bodyColor: UIColor

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        // Hand-build TextKit 1. UITextView's default TextKit 2 stack
        // can't run the BlockDecoratingLayoutManager's overrides.
        let storage = NSTextStorage()
        let layoutManager = BlockDecoratingLayoutManager()
        layoutManager.tintColor = bodyColor
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = BlockTreeTextView(frame: .zero, textContainer: container)
        textView.font = bodyFont
        textView.textColor = bodyColor
        textView.backgroundColor = .clear
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.delegate = context.coordinator
        textView.onEditorCommand = { [weak coordinator = context.coordinator] command in
            guard let coord = coordinator else { return }

            // Inline-format toggles are HOT-path commands — applied
            // as undo-registered storage surgery in the Coordinator
            // (imperative boundary, EDD §22.4.1) instead of routing
            // through the reducer + wholesale attributedText
            // replacement (which destroyed native undo).
            switch command {
            case .toggleBold:          coord.applyInlineToggle(.bold);          return
            case .toggleItalic:        coord.applyInlineToggle(.italic);        return
            case .toggleUnderline:     coord.applyInlineToggle(.underline);     return
            case .toggleStrikethrough: coord.applyInlineToggle(.strikethrough); return
            case .toggleCode:          coord.applyInlineToggle(.code);          return
            default:
                break
            }

            // Everything else hands control to the reducer, whose
            // document mirror may be debounce-stale — sync it first
            // so a reducer-driven mutation can never wholesale-
            // replace away the last few hundred ms of typing.
            if let textView = coord.textView {
                coord.syncDocumentFromStorage(textView)
            }

            // ⌘⇧/ opens the palette without going through
            // `textViewDidChange` (no text was inserted), so the
            // typed-slash pin path doesn't fire. Pin here from the
            // current selection so scroll tracking works for
            // keyboard-shortcut-opened palettes too.
            if case .openSlashPalette = command,
               let textView = coord.textView,
               let start = textView.selectedTextRange?.start {
                coord.pinnedSlashLocation = textView.offset(
                    from: textView.beginningOfDocument,
                    to: start
                )
            }
            coord.parent.onCommand(command)
        }

        context.coordinator.textView = textView

        // Seed initial content from the document.
        let initial = Self.flatten(
            document: document,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        context.coordinator.isApplyingBindingUpdate = true
        textView.attributedText = initial.attributed
        context.coordinator.flattenMap = initial.flattenMap
        context.coordinator.flattenIDMap = initial.flattenIDMap
        context.coordinator.pathIndex = Self.leafPathIndex(document)
        context.coordinator.lastNewlineCount = Self.newlineCount(in: initial.attributed.string as NSString)
        // Default typing attributes for an empty document.
        textView.typingAttributes = Self.typingAttributes(
            for: .paragraph,
            blockID: UUID(),
            groupID: nil,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        context.coordinator.isApplyingBindingUpdate = false

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        // Body re-sync when the SwiftUI side diverges from what the
        // editor already shows. Documents are Equatable; only the
        // shape comparison triggers a re-flatten. Under the
        // imperative boundary (EDD §22.4.1) this is the COLD-path
        // reconciliation — reducer-driven mutations (slash commands,
        // block formats, exit-list) land here; typing and inline
        // toggles never do (the coordinator sets lastSyncedDocument
        // before pushing the binding). Wholesale replacement clears
        // the native undo stack — documented v1 cost of the cold
        // path only.
        if document != context.coordinator.lastSyncedDocument {
            let flattened = Self.flatten(
                document: document,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )
            context.coordinator.isApplyingBindingUpdate = true
            context.coordinator.cancelPendingSync()
            let priorSelection = textView.selectedRange
            textView.attributedText = flattened.attributed
            // Restore caret to a valid position (clamp).
            let clampedLocation = min(priorSelection.location, flattened.attributed.length)
            textView.selectedRange = NSRange(location: clampedLocation, length: 0)
            context.coordinator.flattenMap = flattened.flattenMap
            context.coordinator.flattenIDMap = flattened.flattenIDMap
            context.coordinator.pathIndex = Self.leafPathIndex(document)
            context.coordinator.lastNewlineCount = Self.newlineCount(in: flattened.attributed.string as NSString)
            context.coordinator.lastSyncedDocument = document

            // Fix B3: refresh typingAttributes so the user's NEXT
            // keystroke inherits the chrome at the new cursor leaf.
            // Without this, a slash-command-applied heading would
            // revert to paragraph styling on the next character.
            // Fix L1 (folded into the same call): when the
            // re-flatten produced empty attributedText — typical
            // of wrapping an empty paragraph into a list — fall
            // back to the document at `selection.path` for chrome
            // resolution.
            Self.refreshTypingAttributes(
                textView: textView,
                document: document,
                selection: selection,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )

            context.coordinator.isApplyingBindingUpdate = false
        }

        // Selection re-sync — SEMANTICALLY gated. The flatten maps
        // are rebuilt only at sync points, so their absolute offsets
        // can be stale mid-typing; comparing raw NSRanges against a
        // stale map would "correct" the caret to a wrong position on
        // every keystroke. Bridge the textView's current selection
        // (O(paragraph), always fresh) and only override when the
        // reducer's selection genuinely differs — which happens
        // exactly on reducer-driven mutations, where the maps were
        // just rebuilt by the replace branch above.
        let bridgedCurrent = Self.bridgeSelection(
            storage: textView.attributedText,
            selectedRange: textView.selectedRange,
            pathIndex: context.coordinator.pathIndex
        )
        if selection != bridgedCurrent,
           let nsRange = Self.nsRange(
               for: selection,
               flattenIDMap: context.coordinator.flattenIDMap,
               totalLength: textView.attributedText.length
           ), nsRange != textView.selectedRange {
            context.coordinator.isApplyingBindingUpdate = true
            textView.selectedRange = nsRange
            context.coordinator.isApplyingBindingUpdate = false
        }

        // Clear the slash anchor pin when the palette closes so
        // subsequent scroll events don't republish stale rects to a
        // dismissed popover. Setting the pin happens lazily in
        // `textViewDidChange` / `onEditorCommand`; clearing happens
        // here because the wiring view drives palette open/close
        // through the binding.
        if !isSlashPaletteOpen {
            context.coordinator.pinnedSlashLocation = nil
        }
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        // Teardown flush: if a debounced sync is pending, the reducer
        // is about to receive `.flush` (wiring's onDisappear) with a
        // document missing the tail of the user's typing. Push the
        // final parse through the binding before the view goes away.
        if coordinator.hasPendingSync {
            coordinator.syncDocumentFromStorage(uiView)
        }
    }

    /// Read the chrome / blockID / groupID at the cursor's position
    /// in `textView.attributedText` and set `textView.typingAttributes`
    /// from them. Used after every external-document-driven re-flatten
    /// (B3) so format changes don't revert on the next keystroke.
    ///
    /// **Empty-attributedText fallback (fix L1).** When the document
    /// re-flatten produces a zero-length `attributedText` (e.g.
    /// `applyBlockFormat(.bulletedList)` on an empty paragraph
    /// wraps it to `[bulletList(items: [item(paragraph(empty))])]`
    /// — flatten emits the paragraph's trailing newline then trims
    /// it, leaving zero characters), the textView has no attrs to
    /// read. Without this fallback, `typingAttributes` keeps the
    /// pre-wrap chrome (paragraph), the next keystroke inherits
    /// paragraph chrome, and parse-back silently dissolves the
    /// list back to body text. Resolve from the document at
    /// `selection.path` instead — same chrome the flatten would
    /// have written, with a fresh `groupID` so the next-typed
    /// paragraph groups into this list (parse-back keys list
    /// grouping on chrome+groupID, and a single-item list with a
    /// fresh group id is correct).
    static func refreshTypingAttributes(
        textView: UITextView,
        document: RichTextDocument,
        selection: BlockTreeSelection,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) {
        // Prefer the document-derived path when the attributedText
        // can't supply attrs at the cursor — see fix L1 in the doc
        // comment. The document is also the source of truth for
        // chrome regardless of attributedText state.
        let loc = textView.selectedRange.location
        if loc < textView.attributedText.length {
            let attrs = textView.attributedText.attributes(at: loc, effectiveRange: nil)
            if let chromeRaw = attrs[.blockChrome] as? Int,
               let chrome = BlockChrome(rawValue: chromeRaw) {
                let blockID = (attrs[.blockID] as? UUID) ?? UUID()
                let groupID = attrs[.groupID] as? UUID
                textView.typingAttributes = Self.typingAttributes(
                    for: chrome,
                    blockID: blockID,
                    groupID: groupID,
                    bodyFont: bodyFont,
                    bodyColor: bodyColor
                )
                return
            }
        }

        // Fallback path — resolve from the document selection.
        if let attrs = Self.typingAttributesFromDocument(
            document: document,
            selection: selection,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        ) {
            textView.typingAttributes = attrs
        }
    }

    /// Resolve `typingAttributes` from the document at the
    /// selection path. The chrome reflects the leaf's container
    /// (list → `bulletListItem` / `orderedListItem`, blockquote →
    /// `blockquoteParagraph`) or the leaf's own kind for top-level
    /// blocks. `groupID` is freshly generated — the only thing
    /// parse-back cares about is consistency across paragraphs in
    /// the same group, and a brand-new wrap is by definition a
    /// single-paragraph group.
    static func typingAttributesFromDocument(
        document: RichTextDocument,
        selection: BlockTreeSelection,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) -> [NSAttributedString.Key: Any]? {
        guard let leafID = selection.path.last,
              let leaf = document.block(at: selection.path) else { return nil }

        var chrome: BlockChrome = chromeForLeafKind(leaf.kind)
        var groupID: UUID? = nil

        if selection.path.count >= 2 {
            let containerPath = Array(selection.path.dropLast())
            if let container = document.block(at: containerPath) {
                switch container.kind {
                case .bulletList:
                    chrome = .bulletListItem
                    groupID = UUID()
                case .orderedList:
                    chrome = .orderedListItem
                    groupID = UUID()
                case .blockquote:
                    chrome = .blockquoteParagraph
                    groupID = UUID()
                default:
                    break
                }
            }
        }

        return Self.typingAttributes(
            for: chrome,
            blockID: leafID,
            groupID: groupID,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
    }

    /// Chrome for a leaf based on its own kind only (ignores any
    /// list / blockquote container above it — those override at
    /// the caller).
    private static func chromeForLeafKind(_ kind: Block.Kind) -> BlockChrome {
        switch kind {
        case .paragraph:                return .paragraph
        case .heading(let level, _):
            switch level {
            case 1: return .heading1
            case 2: return .heading2
            default: return .heading3
            }
        case .codeBlock:                return .codeBlock
        case .divider:                  return .divider
        case .bulletList, .orderedList, .blockquote:
            return .paragraph
        }
    }

    // MARK: - Viewport-space caret rect

    /// Return the caret rect at `offset` translated into the
    /// `textView`'s **viewport** coordinate space — i.e. the rect
    /// SwiftUI sees as the local space of the `UIViewRepresentable`.
    ///
    /// `UITextView.caretRect(for:)` returns the rect in the text
    /// container's content space, which equals viewport space only
    /// when `contentOffset == .zero`. The instant the user scrolls,
    /// content y diverges from viewport y by `contentOffset.y`.
    /// SwiftUI's `.popover(attachmentAnchor: .rect(...))` expects
    /// viewport-space rects, so without this translation the
    /// popover anchor drifts as soon as a note grows past one
    /// viewport.
    static func visibleCaretRect(
        in textView: UITextView,
        atOffset offset: Int
    ) -> CGRect {
        guard let position = textView.position(
            from: textView.beginningOfDocument,
            offset: offset
        ) else { return .zero }
        return textView.caretRect(for: position)
            .offsetBy(dx: -textView.contentOffset.x, dy: -textView.contentOffset.y)
    }

    // MARK: - Flatten: RichTextDocument → NSAttributedString

    /// Mapping from a flattened paragraph's NSRange to its source
    /// block path. Used by the coordinator to translate UITextView
    /// selection updates back into `BlockTreeSelection`.
    struct FlattenEntry: Equatable {
        let nsRange: NSRange       // range in the flattened NSAttributedString (excluding trailing \n)
        let blockPath: [UUID]      // path to the leaf this paragraph belongs to
    }

    typealias FlattenMap = [FlattenEntry]
    /// O(1) lookup from leaf id to its flatten entry — read by
    /// `nsRange(for:)` selection bridging so per-keystroke cost stays
    /// bounded regardless of document size (fix S3).
    typealias FlattenIDMap = [UUID: FlattenEntry]

    /// Build an `NSAttributedString` representation of `document` for
    /// the editor + a map from each emitted paragraph's NSRange to
    /// the corresponding block path. The map is read by the selection
    /// bridge and the parse-back path.
    static func flatten(
        document: RichTextDocument,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) -> (attributed: NSAttributedString, flattenMap: FlattenMap, flattenIDMap: FlattenIDMap) {
        let mutable = NSMutableAttributedString()
        var map: FlattenMap = []
        for block in document.blocks {
            appendBlock(
                block,
                pathPrefix: [],
                into: mutable,
                map: &map,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )
        }
        // Flatten emits ONE trailing `\n` per paragraph as the
        // paragraph-attributes carrier. We deliberately don't trim
        // it: an empty list item flattens to just "\n", and the
        // layout manager needs that `\n` as the line-fragment
        // anchor so `drawBullet` has something to position
        // against. Parse-back's `splitParagraphs` already treats
        // the final `\n` as the terminator of its preceding
        // paragraph (not a separator that creates an extra empty
        // trailing paragraph), so the round-trip stays clean.
        // Build the leaf-id → entry index for O(1) bridging.
        var idMap: FlattenIDMap = [:]
        for entry in map {
            if let leafID = entry.blockPath.last {
                idMap[leafID] = entry
            }
        }
        return (mutable, map, idMap)
    }

    private static func appendBlock(
        _ block: Block,
        pathPrefix: [UUID],
        into mutable: NSMutableAttributedString,
        map: inout FlattenMap,
        bodyFont: UIFont,
        bodyColor: UIColor,
        groupID: UUID? = nil,
        inBlockquote: Bool = false
    ) {
        let path = pathPrefix + [block.id]
        switch block.kind {
        case .paragraph(let inline):
            appendLeaf(
                runs: inline,
                blockID: block.id,
                path: path,
                // Fix B7: paragraphs inside a blockquote container
                // emit `.blockquoteParagraph` chrome so parse-back's
                // grouping switch recognizes them as a blockquote
                // container's children. Without this, blockquote
                // round-trips degrade to flat top-level paragraphs.
                chrome: inBlockquote ? .blockquoteParagraph : .paragraph,
                groupID: groupID,
                into: mutable,
                map: &map,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )

        case .heading(let level, let inline):
            let chrome: BlockChrome
            switch level {
            case 1: chrome = .heading1
            case 2: chrome = .heading2
            default: chrome = .heading3
            }
            appendLeaf(
                runs: inline,
                blockID: block.id,
                path: path,
                chrome: chrome,
                groupID: groupID,
                into: mutable,
                map: &map,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )

        case .codeBlock(let text, let languageHint):
            // Code blocks are a single inline run of plain text.
            let runs = [Inline(text: text, marks: [])]
            appendLeaf(
                runs: runs,
                blockID: block.id,
                path: path,
                chrome: .codeBlock,
                groupID: groupID,
                into: mutable,
                map: &map,
                bodyFont: bodyFont,
                bodyColor: bodyColor,
                languageHint: languageHint
            )

        case .divider:
            // Divider has no real text — emit a non-breaking space
            // as a glyph anchor; the layout manager draws the rule.
            let runs = [Inline(text: "\u{00A0}", marks: [])]
            appendLeaf(
                runs: runs,
                blockID: block.id,
                path: path,
                chrome: .divider,
                groupID: groupID,
                into: mutable,
                map: &map,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )

        case .bulletList(let items):
            // Each list item's paragraph emits as its own line with
            // .bulletListItem chrome + the SAME groupID so parse-back
            // can re-group.
            let listGroupID = UUID()
            for item in items {
                for (idx, child) in item.content.enumerated() {
                    if idx == 0, case .paragraph(let inline) = child.kind {
                        appendLeaf(
                            runs: inline,
                            blockID: child.id,
                            path: path + [child.id],
                            chrome: .bulletListItem,
                            groupID: listGroupID,
                            into: mutable,
                            map: &map,
                            bodyFont: bodyFont,
                            bodyColor: bodyColor,
                            listItemID: item.id
                        )
                    } else {
                        // Nested content (rare in v1) — flatten with
                        // the same group id so the parse-back keeps it
                        // associated with the list.
                        appendBlock(
                            child,
                            pathPrefix: path,
                            into: mutable,
                            map: &map,
                            bodyFont: bodyFont,
                            bodyColor: bodyColor,
                            groupID: listGroupID
                        )
                    }
                }
            }

        case .orderedList(let items):
            let listGroupID = UUID()
            for item in items {
                for (idx, child) in item.content.enumerated() {
                    if idx == 0, case .paragraph(let inline) = child.kind {
                        appendLeaf(
                            runs: inline,
                            blockID: child.id,
                            path: path + [child.id],
                            chrome: .orderedListItem,
                            groupID: listGroupID,
                            into: mutable,
                            map: &map,
                            bodyFont: bodyFont,
                            bodyColor: bodyColor,
                            listItemID: item.id
                        )
                    } else {
                        appendBlock(
                            child,
                            pathPrefix: path,
                            into: mutable,
                            map: &map,
                            bodyFont: bodyFont,
                            bodyColor: bodyColor,
                            groupID: listGroupID
                        )
                    }
                }
            }

        case .blockquote(let children):
            let quoteGroupID = UUID()
            for child in children {
                appendBlock(
                    child,
                    pathPrefix: path,
                    into: mutable,
                    map: &map,
                    bodyFont: bodyFont,
                    bodyColor: bodyColor,
                    groupID: quoteGroupID,
                    inBlockquote: true
                )
            }
        }
    }

    /// Build a single paragraph's attributed content — inline runs
    /// rendered with their mark attributes, paragraph-level attrs
    /// (chrome / blockID / groupID / style) applied across, WITHOUT
    /// the trailing newline. Shared by `appendLeaf` (full-document
    /// flatten) and the Coordinator's paragraph-local surgery
    /// (inline-format toggles), so the two paths can't drift apart
    /// in attribute composition.
    static func paragraphContent(
        runs: [Inline],
        chrome: BlockChrome,
        blockID: UUID,
        groupID: UUID?,
        languageHint: String? = nil,
        listItemID: UUID? = nil,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) -> NSMutableAttributedString {
        let mutable = NSMutableAttributedString()
        let font = font(for: chrome, bodyFont: bodyFont)
        let paragraphStyle = paragraphStyle(for: chrome)
        let foreground = foregroundColor(for: chrome, bodyColor: bodyColor)

        // Build the paragraph text by concatenating inline runs.
        for run in runs {
            let runAttributes: [NSAttributedString.Key: Any] = inlineAttributes(
                marks: run.marks,
                baseFont: font,
                baseColor: foreground
            )
            mutable.append(NSAttributedString(string: run.text, attributes: runAttributes))
        }

        // Apply paragraph-level attributes (font fallback,
        // paragraphStyle, blockChrome + blockID + groupID).
        var paragraphAttrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .blockChrome: chrome.rawValue,
            .blockID: blockID
        ]
        if let groupID {
            paragraphAttrs[.groupID] = groupID
        }
        if let languageHint {
            paragraphAttrs[.fromInkLanguageHint] = languageHint
        }
        if let listItemID {
            paragraphAttrs[.fromInkListItemID] = listItemID
        }
        // Apply paragraph attrs only to characters that DON'T already
        // carry a font (so inline-mark-induced fonts persist).
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            if attrs[.font] == nil {
                mutable.addAttribute(.font, value: font, range: range)
            }
            if attrs[.foregroundColor] == nil {
                mutable.addAttribute(.foregroundColor, value: foreground, range: range)
            }
            for (key, value) in paragraphAttrs {
                mutable.addAttribute(key, value: value, range: range)
            }
        }
        return mutable
    }

    private static func appendLeaf(
        runs: [Inline],
        blockID: UUID,
        path: [UUID],
        chrome: BlockChrome,
        groupID: UUID?,
        into mutable: NSMutableAttributedString,
        map: inout FlattenMap,
        bodyFont: UIFont,
        bodyColor: UIColor,
        languageHint: String? = nil,
        listItemID: UUID? = nil
    ) {
        let startLocation = mutable.length
        let font = font(for: chrome, bodyFont: bodyFont)
        let paragraphStyle = paragraphStyle(for: chrome)
        let foreground = foregroundColor(for: chrome, bodyColor: bodyColor)

        let content = paragraphContent(
            runs: runs,
            chrome: chrome,
            blockID: blockID,
            groupID: groupID,
            languageHint: languageHint,
            listItemID: listItemID,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
        mutable.append(content)
        let paragraphRange = NSRange(location: startLocation, length: content.length)

        // Always tag the paragraph attributes even on an empty
        // paragraph (zero-length range can't carry attributes, but
        // we tag the trailing newline below).

        map.append(FlattenEntry(nsRange: paragraphRange, blockPath: path))

        // Newline separator between paragraphs. The newline itself
        // carries the SAME paragraph attributes so the layout
        // manager's chrome painting extends to the end of the line
        // fragment.
        let newline = NSMutableAttributedString(string: "\n")
        var newlineAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraphStyle,
            .blockChrome: chrome.rawValue,
            .blockID: blockID
        ]
        if let groupID {
            newlineAttrs[.groupID] = groupID
        }
        if let languageHint {
            newlineAttrs[.fromInkLanguageHint] = languageHint
        }
        if let listItemID {
            newlineAttrs[.fromInkListItemID] = listItemID
        }
        newline.addAttributes(newlineAttrs, range: NSRange(location: 0, length: 1))
        mutable.append(newline)
    }

    // MARK: - Inline marks → NSAttributedString attributes

    private static func inlineAttributes(
        marks: [Mark],
        baseFont: UIFont,
        baseColor: UIColor
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]
        var font = baseFont
        var foreground = baseColor

        var symbolicTraits = font.fontDescriptor.symbolicTraits
        var underline: NSUnderlineStyle? = nil
        var strikethrough: NSUnderlineStyle? = nil
        var backgroundColor: UIColor? = nil

        for mark in marks {
            switch mark {
            case .bold:
                symbolicTraits.insert(.traitBold)
            case .italic:
                symbolicTraits.insert(.traitItalic)
            case .underline:
                underline = .single
            case .strikethrough:
                strikethrough = .single
            case .code:
                font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                symbolicTraits = font.fontDescriptor.symbolicTraits
                backgroundColor = UIColor.label.withAlphaComponent(0.06)
                // Custom key so parse-back recovers the Mark.code
                // without inferring from font + background (which is
                // ambiguous).
                attrs[.fromInkInlineCode] = true
            case .highlight(let kind):
                backgroundColor = color(for: kind)
                // Custom key carries the semantic kind for parse-back;
                // .backgroundColor alone doesn't uniquely identify the
                // mark.
                attrs[.fromInkHighlightKind] = kind.rawValue
            case .link(let url):
                attrs[.link] = url
                underline = .single
                foreground = UIColor.systemBlue
            }
        }

        if let updatedDescriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits) {
            font = UIFont(descriptor: updatedDescriptor, size: 0)
        }
        attrs[.font] = font
        attrs[.foregroundColor] = foreground
        if let underline { attrs[.underlineStyle] = underline.rawValue }
        if let strikethrough { attrs[.strikethroughStyle] = strikethrough.rawValue }
        if let backgroundColor { attrs[.backgroundColor] = backgroundColor }
        return attrs
    }

    private static func color(for kind: HighlightKind) -> UIColor {
        switch kind {
        case .yellow: return UIColor.systemYellow.withAlphaComponent(0.35)
        case .red:    return UIColor.systemRed.withAlphaComponent(0.25)
        case .blue:   return UIColor.systemBlue.withAlphaComponent(0.20)
        case .green:  return UIColor.systemGreen.withAlphaComponent(0.25)
        }
    }

    // MARK: - Per-chrome typography

    private static func font(for chrome: BlockChrome, bodyFont: UIFont) -> UIFont {
        switch chrome {
        case .paragraph, .bulletListItem, .orderedListItem, .divider:
            return bodyFont
        case .heading1:
            return makeSerif(size: 28, weight: .semibold, fallback: UIFont.systemFont(ofSize: 28, weight: .semibold))
        case .heading2:
            return makeSerif(size: 22, weight: .semibold, fallback: UIFont.systemFont(ofSize: 22, weight: .semibold))
        case .heading3:
            return makeSerif(size: 18, weight: .semibold, fallback: UIFont.systemFont(ofSize: 18, weight: .semibold))
        case .codeBlock:
            return UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
        case .blockquoteParagraph:
            // Italic variant of the body font for the quote feel.
            if let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                return UIFont(descriptor: descriptor, size: 0)
            }
            return bodyFont
        }
    }

    private static func makeSerif(size: CGFloat, weight: UIFont.Weight, fallback: UIFont) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return fallback
    }

    private static func foregroundColor(for chrome: BlockChrome, bodyColor: UIColor) -> UIColor {
        switch chrome {
        case .codeBlock:
            return bodyColor.withAlphaComponent(0.85)
        default:
            return bodyColor
        }
    }

    private static func paragraphStyle(for chrome: BlockChrome) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        style.paragraphSpacingBefore = 4
        switch chrome {
        case .heading1, .heading2, .heading3:
            style.paragraphSpacingBefore = 10
            style.paragraphSpacing = 6
        case .bulletListItem, .orderedListItem:
            style.firstLineHeadIndent = 28
            style.headIndent = 28
        case .blockquoteParagraph:
            style.firstLineHeadIndent = 20
            style.headIndent = 20
        case .codeBlock:
            style.firstLineHeadIndent = 12
            style.headIndent = 12
        default:
            break
        }
        return style
    }

    // MARK: - Typing attributes

    /// Attribute set for `UITextView.typingAttributes` — what newly
    /// inserted characters inherit. Must be reset after every block-
    /// format change so the user's next keystroke keeps the styling.
    static func typingAttributes(
        for chrome: BlockChrome,
        blockID: UUID,
        groupID: UUID?,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: chrome, bodyFont: bodyFont),
            .foregroundColor: foregroundColor(for: chrome, bodyColor: bodyColor),
            .paragraphStyle: paragraphStyle(for: chrome),
            .blockChrome: chrome.rawValue,
            .blockID: blockID
        ]
        if let groupID {
            attrs[.groupID] = groupID
        }
        return attrs
    }

    // MARK: - Parse-back: NSAttributedString → RichTextDocument

    static func parseBack(_ attributed: NSAttributedString) -> RichTextDocument {
        // Walk paragraphs, emit blocks, group consecutive same-group
        // paragraphs into containers.
        let paragraphs = splitParagraphs(attributed)

        var topLevel: [Block] = []
        // Track emitted block IDs to detect collisions caused by
        // Enter inheriting the prior paragraph's .blockID via
        // typingAttributes (fix B1). A duplicate gets a fresh UUID.
        var seenBlockIDs: Set<UUID> = []

        var pendingGroupID: UUID? = nil
        var pendingGroupChrome: BlockChrome? = nil
        var pendingGroupBlocks: [Block] = []
        var pendingGroupItemIDs: [UUID?] = []  // listItemID per emitted block (for bullet/ordered lists)

        func flushPendingGroup() {
            guard let chrome = pendingGroupChrome, !pendingGroupBlocks.isEmpty else {
                pendingGroupID = nil
                pendingGroupChrome = nil
                pendingGroupBlocks = []
                pendingGroupItemIDs = []
                return
            }
            switch chrome {
            case .bulletListItem:
                let items = zip(pendingGroupBlocks, pendingGroupItemIDs).map { block, itemID in
                    ListItem(id: itemID ?? UUID(), content: [block])
                }
                topLevel.append(Block(kind: .bulletList(items: items)))
            case .orderedListItem:
                let items = zip(pendingGroupBlocks, pendingGroupItemIDs).map { block, itemID in
                    ListItem(id: itemID ?? UUID(), content: [block])
                }
                topLevel.append(Block(kind: .orderedList(items: items)))
            case .blockquoteParagraph:
                topLevel.append(Block(kind: .blockquote(children: pendingGroupBlocks)))
            default:
                topLevel.append(contentsOf: pendingGroupBlocks)
            }
            pendingGroupID = nil
            pendingGroupChrome = nil
            pendingGroupBlocks = []
            pendingGroupItemIDs = []
        }

        for paragraph in paragraphs {
            let chrome = paragraph.chrome
            let groupID = paragraph.groupID

            // Fix B1: dedupe collisions BEFORE building the leaf so
            // the resulting Block.id is unique.
            var effectiveID = paragraph.blockID
            if seenBlockIDs.contains(effectiveID) {
                effectiveID = UUID()
            }
            seenBlockIDs.insert(effectiveID)
            let leafBlock = buildLeafBlock(from: paragraph, overrideID: effectiveID)

            // Group-handling: bullets, ordered, blockquote children.
            switch chrome {
            case .bulletListItem, .orderedListItem, .blockquoteParagraph:
                if pendingGroupID != nil, pendingGroupID == groupID, pendingGroupChrome == chrome {
                    pendingGroupBlocks.append(leafBlock)
                    pendingGroupItemIDs.append(paragraph.listItemID)
                } else {
                    flushPendingGroup()
                    pendingGroupID = groupID
                    pendingGroupChrome = chrome
                    pendingGroupBlocks = [leafBlock]
                    pendingGroupItemIDs = [paragraph.listItemID]
                }
            default:
                flushPendingGroup()
                topLevel.append(leafBlock)
            }
        }
        flushPendingGroup()

        return RichTextDocument(blocks: topLevel)
    }

    private struct ParagraphSlice {
        let nsRange: NSRange
        let text: String
        let chrome: BlockChrome
        let blockID: UUID
        let groupID: UUID?
        let languageHint: String?
        let listItemID: UUID?
        let inlineRuns: [Inline]
    }

    private static func splitParagraphs(_ attributed: NSAttributedString) -> [ParagraphSlice] {
        let full = attributed.string as NSString
        var slices: [ParagraphSlice] = []
        var cursor = 0
        while cursor < full.length {
            let nlRange = full.range(of: "\n", options: [], range: NSRange(location: cursor, length: full.length - cursor))
            let paragraphEnd = nlRange.location != NSNotFound ? nlRange.location : full.length
            let paragraphRange = NSRange(location: cursor, length: paragraphEnd - cursor)
            if paragraphRange.length > 0 || cursor == 0 || cursor > 0 {
                // Read paragraph metadata from the first character.
                let metaLocation = paragraphRange.length > 0
                    ? paragraphRange.location
                    : max(0, paragraphRange.location - 1)
                let attrs = attributed.attributes(at: metaLocation, effectiveRange: nil)
                let chromeRaw = (attrs[.blockChrome] as? Int) ?? BlockChrome.paragraph.rawValue
                let chrome = BlockChrome(rawValue: chromeRaw) ?? .paragraph
                let blockID = (attrs[.blockID] as? UUID) ?? UUID()
                let groupID = attrs[.groupID] as? UUID
                let languageHint = attrs[.fromInkLanguageHint] as? String
                let listItemID = attrs[.fromInkListItemID] as? UUID
                let paragraphText = full.substring(with: paragraphRange)
                let inlineRuns = parseInlineRuns(
                    attributed: attributed,
                    range: paragraphRange,
                    chrome: chrome
                )
                slices.append(ParagraphSlice(
                    nsRange: paragraphRange,
                    text: paragraphText,
                    chrome: chrome,
                    blockID: blockID,
                    groupID: groupID,
                    languageHint: languageHint,
                    listItemID: listItemID,
                    inlineRuns: inlineRuns
                ))
            }
            if nlRange.location == NSNotFound { break }
            cursor = paragraphEnd + 1
        }
        return slices
    }

    private static func parseInlineRuns(
        attributed: NSAttributedString,
        range: NSRange,
        chrome: BlockChrome
    ) -> [Inline] {
        guard range.length > 0 else { return [] }
        if chrome == .codeBlock || chrome == .divider {
            // codeBlock has no marks; divider's anchor character is
            // discarded by the leaf builder.
            return [Inline(
                text: (attributed.string as NSString).substring(with: range),
                marks: []
            )]
        }
        var runs: [Inline] = []
        attributed.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            let runText = (attributed.string as NSString).substring(with: runRange)
            let marks = marksFor(attrs: attrs)
            runs.append(Inline(text: runText, marks: marks))
        }
        // Coalesce adjacent runs with equal marks.
        var coalesced: [Inline] = []
        for run in runs {
            if var last = coalesced.last, last.marks == run.marks {
                last.text.append(run.text)
                coalesced[coalesced.count - 1] = last
            } else {
                coalesced.append(run)
            }
        }
        return coalesced
    }

    private static func marksFor(attrs: [NSAttributedString.Key: Any]) -> [Mark] {
        var marks: [Mark] = []
        // Code is checked first so the bold/italic traits inferred
        // from the monospaced font don't accidentally emit bold/italic
        // marks. A code mark's font is monospaced, not bold/italic.
        let hasCode = (attrs[.fromInkInlineCode] as? Bool) ?? false
        if hasCode {
            marks.append(.code)
        } else if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) { marks.append(.bold) }
            if traits.contains(.traitItalic) { marks.append(.italic) }
        }
        if (attrs[.underlineStyle] as? Int) ?? 0 != 0 {
            marks.append(.underline)
        }
        if (attrs[.strikethroughStyle] as? Int) ?? 0 != 0 {
            marks.append(.strikethrough)
        }
        if let url = attrs[.link] as? URL {
            marks.append(.link(url))
        }
        if let kindRaw = attrs[.fromInkHighlightKind] as? String,
           let kind = HighlightKind(rawValue: kindRaw) {
            marks.append(.highlight(kind))
        }
        return marks
    }

    private static func buildLeafBlock(from slice: ParagraphSlice, overrideID: UUID) -> Block {
        switch slice.chrome {
        case .paragraph, .bulletListItem, .orderedListItem, .blockquoteParagraph:
            return Block(id: overrideID, kind: .paragraph(inline: slice.inlineRuns))
        case .heading1:
            return Block(id: overrideID, kind: .heading(level: 1, inline: slice.inlineRuns))
        case .heading2:
            return Block(id: overrideID, kind: .heading(level: 2, inline: slice.inlineRuns))
        case .heading3:
            return Block(id: overrideID, kind: .heading(level: 3, inline: slice.inlineRuns))
        case .codeBlock:
            return Block(id: overrideID, kind: .codeBlock(text: slice.text, languageHint: slice.languageHint))
        case .divider:
            return Block(id: overrideID, kind: .divider)
        }
    }

    // MARK: - Selection bridge

    /// Find the BlockTreeSelection's NSRange in the flattened
    /// attributedText. Uses the leaf-id dictionary for O(1) lookup.
    /// Returns nil if the path no longer resolves or the offsets
    /// exceed the leaf's text length.
    static func nsRange(
        for selection: BlockTreeSelection,
        flattenIDMap: FlattenIDMap,
        totalLength: Int
    ) -> NSRange? {
        guard let leafID = selection.path.last,
              let entry = flattenIDMap[leafID] else { return nil }
        // Clamp offsets to the leaf's text length so out-of-range
        // values from a stale selection don't return invalid NSRange.
        let start = max(0, min(selection.startUTF16, entry.nsRange.length))
        let end = max(start, min(selection.endUTF16, entry.nsRange.length))
        let location = entry.nsRange.location + start
        let length = end - start
        guard location + length <= totalLength else { return nil }
        return NSRange(location: location, length: length)
    }

    /// Convert a UITextView NSRange into a BlockTreeSelection by
    /// finding which paragraph entry the range falls in.
    ///
    /// **Multi-paragraph selections (fix S2).** If the NSRange spans
    /// two or more paragraphs (start in paragraph A, end in paragraph
    /// B), the returned selection's `path` is paragraph A's path and
    /// `endUTF16` is clamped to A's text length. This matches the
    /// "single-leaf selection invariant" the reducer's
    /// `toggleInlineFormat` assumes; the alternative — multi-leaf
    /// selection model — is a separate piece of work.
    static func selection(
        forNSRange nsRange: NSRange,
        flattenMap: FlattenMap
    ) -> BlockTreeSelection {
        guard let entry = flattenMap.first(where: { entry in
            entry.nsRange.location <= nsRange.location
                && nsRange.location <= entry.nsRange.location + entry.nsRange.length
        }) else {
            return BlockTreeSelection()
        }
        let startLocal = nsRange.location - entry.nsRange.location
        let endLocal = startLocal + nsRange.length
        return BlockTreeSelection(
            path: entry.blockPath,
            startUTF16: startLocal,
            // Clamp end to the host leaf's text length so a multi-
            // paragraph drag doesn't produce a selection that
            // overruns the leaf — see method doc.
            endUTF16: max(startLocal, min(endLocal, entry.nsRange.length))
        )
    }

    // MARK: - Storage-side bridging (pure, testable)

    /// Leaf-id → full block path for every leaf in `document`. Rebuilt
    /// once per document sync (NOT per keystroke); the selection
    /// bridge reads it so caret moves cost O(paragraph), never a
    /// full-document walk. Path convention matches
    /// `RichTextDocument.block(at:)` — container ids included,
    /// ListItem ids skipped.
    static func leafPathIndex(_ document: RichTextDocument) -> [UUID: [UUID]] {
        var index: [UUID: [UUID]] = [:]
        func walk(_ block: Block, prefix: [UUID]) {
            let path = prefix + [block.id]
            if block.isLeaf {
                index[block.id] = path
            }
            for child in block.descendants {
                walk(child, prefix: path)
            }
        }
        for block in document.blocks {
            walk(block, prefix: [])
        }
        return index
    }

    /// The paragraph's text range (EXCLUDING the trailing `\n`)
    /// containing `location`, plus the probe location that carries the
    /// paragraph's attributes — the first character, or the trailing
    /// `\n` for an empty paragraph (flatten and `typingAttributes`
    /// both tag the newline). `probe == nil` when the storage is
    /// empty.
    static func paragraphSlice(
        at location: Int,
        in storage: NSAttributedString
    ) -> (textRange: NSRange, probe: Int?) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return (NSRange(location: 0, length: 0), nil) }
        let clamped = max(0, min(location, ns.length))
        let para = ns.paragraphRange(for: NSRange(location: clamped, length: 0))
        // paragraphRange includes the trailing newline — exclude it.
        var textLength = para.length
        if textLength > 0, ns.character(at: para.location + textLength - 1) == 0x0A {
            textLength -= 1
        }
        let textRange = NSRange(location: para.location, length: textLength)
        let probe: Int?
        if textRange.length > 0 {
            probe = textRange.location
        } else if textRange.location < ns.length {
            probe = textRange.location          // the trailing \n itself
        } else if textRange.location > 0 {
            probe = textRange.location - 1      // final \n of the document
        } else {
            probe = nil
        }
        return (textRange, probe)
    }

    /// Bridge a UITextView selection into `BlockTreeSelection` by
    /// reading the `.blockID` attribute at the caret's paragraph and
    /// resolving the full path through `pathIndex`. O(paragraph) —
    /// replaces the flatten-map scan that previously required a full
    /// re-flatten per keystroke to stay fresh.
    ///
    /// Contract parity with the map-based bridge:
    ///   - Multi-paragraph ranges clamp `endUTF16` to the host
    ///     paragraph (single-leaf selection invariant, fix S2).
    ///   - A caret on the phantom empty line AFTER the document's
    ///     final `\n` returns the unset selection (empty path) —
    ///     block-format actions resolve unset to the last leaf.
    static func bridgeSelection(
        storage: NSAttributedString,
        selectedRange: NSRange,
        pathIndex: [UUID: [UUID]]
    ) -> BlockTreeSelection {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return BlockTreeSelection() }
        // Caret past the final newline → unset (matches the old
        // bridge, whose map entries never cover that position).
        if selectedRange.location >= ns.length,
           ns.character(at: ns.length - 1) == 0x0A {
            return BlockTreeSelection()
        }
        let (textRange, probe) = paragraphSlice(at: selectedRange.location, in: storage)
        guard let probe, probe < storage.length,
              let blockID = storage.attribute(.blockID, at: probe, effectiveRange: nil) as? UUID else {
            return BlockTreeSelection()
        }
        // Fall back to a top-level path when the index hasn't seen
        // this leaf yet (brand-new paragraph typed since the last
        // sync; the next sync creates the block with this id).
        let path = pathIndex[blockID] ?? [blockID]
        let start = max(0, selectedRange.location - textRange.location)
        let absoluteEnd = min(selectedRange.location + selectedRange.length, textRange.location + textRange.length)
        let end = max(start, absoluteEnd - textRange.location)
        return BlockTreeSelection(
            path: path,
            startUTF16: min(start, textRange.length),
            endUTF16: min(end, textRange.length)
        )
    }

    /// Rebuild the flatten maps by walking the STORAGE's paragraphs
    /// and resolving paths through `pathIndex` — no throwaway
    /// re-flatten of the whole document. Ranges exclude each
    /// paragraph's trailing `\n`, matching `flatten`'s map contract.
    static func maps(
        fromStorage storage: NSAttributedString,
        pathIndex: [UUID: [UUID]]
    ) -> (flattenMap: FlattenMap, flattenIDMap: FlattenIDMap) {
        let ns = storage.string as NSString
        var map: FlattenMap = []
        var idMap: FlattenIDMap = [:]
        var cursor = 0
        while cursor < ns.length {
            let (textRange, probe) = paragraphSlice(at: cursor, in: storage)
            if let probe, probe < storage.length,
               let blockID = storage.attribute(.blockID, at: probe, effectiveRange: nil) as? UUID {
                let path = pathIndex[blockID] ?? [blockID]
                let entry = FlattenEntry(nsRange: textRange, blockPath: path)
                map.append(entry)
                idMap[blockID] = entry
            }
            cursor = textRange.location + textRange.length + 1  // skip the \n
        }
        return (map, idMap)
    }

    /// Count of `\n` characters — the structural-change discriminator.
    /// A keystroke that doesn't change the paragraph count needs no
    /// parse-back; one that does (Enter, paste with newlines,
    /// cross-paragraph delete) syncs the document immediately.
    static func newlineCount(in string: NSString) -> Int {
        var count = 0
        var cursor = 0
        while cursor < string.length {
            let next = string.range(of: "\n", options: [], range: NSRange(location: cursor, length: string.length - cursor))
            if next.location == NSNotFound { break }
            count += 1
            cursor = next.location + 1
        }
        return count
    }

    /// Storage-side slash filter: the text between the pinned trigger
    /// `/` and the end of its paragraph. Returns nil when the trigger
    /// is no longer a `/` at that location (user deleted past it) —
    /// the caller dismisses the palette. Replaces the reducer-side
    /// per-keystroke document walk for live filtering; the reducer's
    /// document-based refresh still runs on each (debounced)
    /// `documentEdited` and converges to the same value.
    static func slashFilter(
        storage: NSAttributedString,
        triggerLocation: Int
    ) -> String? {
        let ns = storage.string as NSString
        guard triggerLocation >= 0, triggerLocation < ns.length,
              ns.character(at: triggerLocation) == 0x2F else { return nil }
        let (textRange, _) = paragraphSlice(at: triggerLocation, in: storage)
        let filterStart = triggerLocation + 1
        let filterEnd = textRange.location + textRange.length
        guard filterStart <= filterEnd else { return "" }
        return ns.substring(with: NSRange(location: filterStart, length: filterEnd - filterStart))
    }

    /// Storage-side variant of `shouldExitList`: Enter at a caret on
    /// an EMPTY list-item paragraph exits the list. Reads emptiness
    /// and chrome from the storage rather than the (possibly
    /// debounce-stale) document, so a just-typed-then-deleted item
    /// still exits correctly.
    static func shouldExitList(
        replacementText text: String,
        replacementRange range: NSRange,
        storage: NSAttributedString
    ) -> Bool {
        guard text == "\n", range.length == 0 else { return false }
        let (textRange, probe) = paragraphSlice(at: range.location, in: storage)
        // The probe must be the caret paragraph's OWN terminator
        // (`probe == textRange.location`), never the previous
        // paragraph's via the phantom-tail fallback. At the phantom
        // position after the document's final `\n`, the fallback
        // probe reads the PRECEDING paragraph's list chrome — firing
        // exitList against an unset selection, which no-ops in the
        // reducer while the suppressed newline makes Return appear
        // dead. (The caret clamp in textViewDidChangeSelection keeps
        // carets off the phantom position entirely; this guard is the
        // pure-function half of the same invariant.)
        guard textRange.length == 0,
              let probe, probe == textRange.location, probe < storage.length,
              let chromeRaw = storage.attribute(.blockChrome, at: probe, effectiveRange: nil) as? Int,
              let chrome = BlockChrome(rawValue: chromeRaw) else { return false }
        return chrome == .bulletListItem || chrome == .orderedListItem
    }

    /// Merge From Ink's custom keys back into UIKit-derived typing
    /// attributes.
    ///
    /// **Why this exists (the disappearing-bullet bug).** UIKit
    /// re-derives `typingAttributes` on EVERY selection change — tap,
    /// arrow key, programmatic `selectedRange` set — and the derived
    /// dictionary contains ONLY standard attributes; custom keys are
    /// dropped (verified empirically 2026-06-10 on the iOS 26
    /// simulator). The first character typed after any caret move
    /// therefore carried no `.blockChrome` / `.blockID`, the
    /// paragraph probed as chromeless, the bullet/number/quote chrome
    /// vanished, and parse-back dissolved the block to a body
    /// paragraph.
    ///
    /// The merge keeps UIKit's derived standard attributes (correct
    /// inline continuation — bold keeps flowing after bold text) and
    /// re-asserts:
    ///   - paragraph-identity keys (`.blockChrome`, `.blockID`,
    ///     `.groupID`, `.fromInkListItemID`, `.fromInkLanguageHint`)
    ///     from the caret paragraph's probe character, and
    ///   - custom inline-mark keys (`.fromInkInlineCode`,
    ///     `.fromInkHighlightKind`) from the character preceding the
    ///     caret, same-paragraph only — mirroring UIKit's own
    ///     continuation rule for standard attributes.
    static func typingAttributesPreservingChrome(
        derived: [NSAttributedString.Key: Any],
        storage: NSAttributedString,
        caretLocation: Int,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) -> [NSAttributedString.Key: Any] {
        // Empty storage: nothing to probe, and the derived attributes
        // are whatever the user last edited — after deleting an
        // entire list that means list chrome plus the 28pt indent
        // paragraph style, leaving the caret visually indented in an
        // "empty" note and the next character resurrecting the list.
        // Reset to body-paragraph typing attributes (same shape
        // makeUIView seeds for an empty document).
        guard storage.length > 0 else {
            return typingAttributes(
                for: .paragraph,
                blockID: UUID(),
                groupID: nil,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )
        }
        let (textRange, probe) = paragraphSlice(at: caretLocation, in: storage)
        guard let probe, probe < storage.length else { return derived }

        var merged = derived
        let paragraphAttrs = storage.attributes(at: probe, effectiveRange: nil)
        let identityKeys: [NSAttributedString.Key] = [
            .blockChrome, .blockID, .groupID, .fromInkListItemID, .fromInkLanguageHint
        ]
        for key in identityKeys {
            merged[key] = paragraphAttrs[key]
        }

        let inlineKeys: [NSAttributedString.Key] = [.fromInkInlineCode, .fromInkHighlightKind]
        let precedingLocation = caretLocation - 1
        if precedingLocation >= textRange.location, precedingLocation < storage.length, precedingLocation >= 0 {
            let preceding = storage.attributes(at: precedingLocation, effectiveRange: nil)
            for key in inlineKeys {
                merged[key] = preceding[key]
            }
        } else {
            for key in inlineKeys {
                merged[key] = nil
            }
        }
        return merged
    }

    /// Typing on the phantom tail line (the caret position AFTER the
    /// document's final `\n`) creates a new paragraph whose
    /// `.blockID` duplicates its predecessor's via `typingAttributes`
    /// — WITHOUT changing the newline count, so the structural
    /// detector doesn't fire. O(1) probe of the tail paragraph
    /// against its predecessor; when true, the caller runs the same
    /// identity fixups a structural edit would.
    static func tailParagraphNeedsIdentityFixup(in storage: NSAttributedString) -> Bool {
        let ns = storage.string as NSString
        guard ns.length > 0, ns.character(at: ns.length - 1) != 0x0A else { return false }
        let (tail, probe) = paragraphSlice(at: ns.length - 1, in: storage)
        guard tail.location > 0,
              let probe, probe < storage.length,
              let tailID = storage.attribute(.blockID, at: probe, effectiveRange: nil) as? UUID,
              let prevID = storage.attribute(.blockID, at: tail.location - 1, effectiveRange: nil) as? UUID
        else { return false }
        return tailID == prevID
    }

    // MARK: - Paragraph identity hygiene (structural edits)

    /// One planned attribute fix for a paragraph whose `.blockID`
    /// duplicates an earlier paragraph's — the inheritance artifact of
    /// `typingAttributes` carrying the prior paragraph's identity
    /// across a native Enter (or an in-app rich paste). Detection is
    /// pure so it can be unit-tested without a UITextView.
    struct ParagraphIdentityFixup: Equatable {
        /// Paragraph range INCLUDING the trailing `\n` (the newline
        /// carries the paragraph attrs and must be retagged too).
        let range: NSRange
        let freshBlockID: UUID
        /// Non-nil when the duplicate must also change chrome —
        /// heading split demotes the second half to body (matches
        /// Notion / Bear / Apple Notes and the reducer's
        /// `insertParagraphAtCursor`).
        let demoteToParagraph: Bool
        /// Non-nil when the duplicate is a list item — the new row
        /// needs its own ListItem identity while staying in the same
        /// group.
        let freshListItemID: UUID?
    }

    /// Detect duplicate-`.blockID` paragraphs after a structural edit.
    /// The FIRST paragraph carrying an id keeps it (it's the original
    /// — Enter splits leave the first half in place); each subsequent
    /// duplicate gets a fresh id, plus a chrome demotion when the
    /// duplicate is a heading (Enter-on-heading drops to body) and a
    /// fresh ListItem id when it's a list row.
    static func paragraphIdentityFixups(
        in storage: NSAttributedString
    ) -> [ParagraphIdentityFixup] {
        let ns = storage.string as NSString
        var seen: Set<UUID> = []
        var fixups: [ParagraphIdentityFixup] = []
        var cursor = 0
        while cursor < ns.length {
            let (textRange, probe) = paragraphSlice(at: cursor, in: storage)
            let hasTrailingNewline = textRange.location + textRange.length < ns.length
            let fullRange = NSRange(
                location: textRange.location,
                length: textRange.length + (hasTrailingNewline ? 1 : 0)
            )
            if let probe, probe < storage.length {
                let attrs = storage.attributes(at: probe, effectiveRange: nil)
                if let blockID = attrs[.blockID] as? UUID {
                    if seen.contains(blockID) {
                        let chrome = (attrs[.blockChrome] as? Int).flatMap(BlockChrome.init(rawValue:))
                        let isHeading = chrome == .heading1 || chrome == .heading2 || chrome == .heading3
                        let isListItem = chrome == .bulletListItem || chrome == .orderedListItem
                        fixups.append(ParagraphIdentityFixup(
                            range: fullRange,
                            freshBlockID: UUID(),
                            demoteToParagraph: isHeading,
                            freshListItemID: isListItem ? UUID() : nil
                        ))
                    } else {
                        seen.insert(blockID)
                    }
                }
            }
            cursor = fullRange.location + max(fullRange.length, 1)
        }
        return fixups
    }

    // MARK: - Slash trigger evaluation (pure, testable)

    /// Result of evaluating whether a single text change armed a
    /// pending slash trigger. The Coordinator stores `.armed` and
    /// clears on `.clear`; nothing else fires `onSlashTyped`.
    enum SlashTriggerEvaluation: Equatable {
        case armed(location: Int)
        case clear
    }

    /// Pure function: given a `shouldChangeTextIn` replacement and
    /// the current pre-mutation text, decide whether to arm a
    /// pending slash trigger. Lives outside the Coordinator so it
    /// can be unit-tested without a UITextView.
    ///
    /// Trigger semantics:
    ///   1. The replacement text must be exactly `"/"`. Multi-character
    ///      replacements (paste, autocorrect, predictive insert) do
    ///      NOT arm — v1 limitation.
    ///   2. The character BEFORE `range.location` must be a paragraph
    ///      boundary: either the start of the document, a newline,
    ///      or any Unicode whitespace (`Character.isWhitespace`,
    ///      which covers tab, non-breaking space, ideographic space,
    ///      em/en spaces, and Unicode whitespace generally).
    ///   3. The previous character is read by Character (grapheme
    ///      cluster), NOT by UTF-16 code unit — so a slash typed
    ///      after an emoji or a flag is correctly evaluated against
    ///      the FULL preceding cluster, not a lone surrogate.
    static func evaluateSlashTrigger(
        replacementText text: String,
        replacementRange range: NSRange,
        currentText: String
    ) -> SlashTriggerEvaluation {
        guard text == "/" else { return .clear }
        if range.location == 0 { return .armed(location: range.location) }

        // Find the character immediately preceding the replacement
        // range. `range.location` is in UTF-16 code units; we need
        // to walk back to the previous grapheme cluster boundary.
        let utf16 = currentText.utf16
        guard range.location <= utf16.count else { return .clear }
        let cutoff = utf16.index(utf16.startIndex, offsetBy: range.location)
        let prefix = String(utf16[utf16.startIndex..<cutoff]) ?? ""
        guard let prev = prefix.last else {
            return .armed(location: range.location)
        }
        if prev.isNewline || prev.isWhitespace {
            return .armed(location: range.location)
        }
        return .clear
    }

    // MARK: - Exit-list trigger evaluation (pure, testable)

    /// Decide whether a `\n` insertion on an empty list-item
    /// paragraph should fire `.exitList` instead of letting UIKit
    /// insert a fresh empty item. Pure for testability — no
    /// `UITextView` access, only the inputs the Coordinator already
    /// has at the `shouldChangeTextIn` call site.
    ///
    /// Conditions (all must hold):
    ///   1. The replacement is exactly `"\n"` with `length == 0`
    ///      (Enter at a caret, not Enter replacing a selection).
    ///   2. The caret's leaf path resolves to a paragraph inside a
    ///      `bulletList` or `orderedList`. The path's second-to-last
    ///      component is the container — we walk it via
    ///      `document.block(at:)` and switch on `kind`.
    ///   3. The leaf paragraph is empty (`joinedInlineText` is empty
    ///      or nil). Non-empty list items get the normal Enter
    ///      behavior (split into a fresh item).
    static func shouldExitList(
        replacementText text: String,
        replacementRange range: NSRange,
        selection: BlockTreeSelection,
        document: RichTextDocument
    ) -> Bool {
        guard text == "\n", range.length == 0 else { return false }
        guard selection.path.count >= 2 else { return false }
        // Container is one level up from the leaf.
        let containerPath = Array(selection.path.dropLast())
        guard let container = document.block(at: containerPath) else { return false }
        switch container.kind {
        case .bulletList, .orderedList:
            break
        default:
            return false
        }
        guard let leaf = document.block(at: selection.path) else { return false }
        let text = leaf.joinedInlineText ?? ""
        return text.isEmpty
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextKitEditorView
        weak var textView: UITextView?

        /// Last document the view rendered. Used as the diff key in
        /// `updateUIView` so we don't re-flatten on every render.
        var lastSyncedDocument: RichTextDocument

        /// Latest flatten map — kept in sync with `textView.attributedText`.
        var flattenMap: FlattenMap = []

        /// O(1) leaf-id → flatten entry. Updated alongside `flattenMap`;
        /// `lastSyncedDocument` is the document both were computed from
        /// (invariant: all three move together).
        var flattenIDMap: FlattenIDMap = [:]

        /// Leaf-id → full block path, rebuilt at every document sync.
        /// The per-keystroke selection bridge reads this so caret
        /// moves cost O(paragraph) instead of a map scan over a
        /// freshly re-flattened document.
        var pathIndex: [UUID: [UUID]] = [:]

        /// `\n` count at the last sync — the structural-change
        /// discriminator. A didChange that doesn't move this number
        /// didn't add/remove/merge paragraphs and needs no immediate
        /// parse-back.
        var lastNewlineCount: Int = 0

        /// In-flight debounced document sync (typing path). Cancelled
        /// and superseded by every keystroke; flushed immediately on
        /// structural change, palette interaction, command handoff,
        /// end-editing, and teardown.
        private var syncTask: Task<Void, Never>? = nil

        /// Set while we're programmatically applying a binding-driven
        /// update; suppresses the delegate did-change callbacks so a
        /// binding write doesn't loop into another binding write.
        var isApplyingBindingUpdate = false

        /// NSRange location of a `/` typed at a word boundary. Set in
        /// `shouldChangeTextIn` and consumed in `textViewDidChange`
        /// AFTER the flatten map is freshly rebuilt from the parsed
        /// document. iOS 26's UITextView fires `textViewDidChange`
        /// after the next runloop iteration (not synchronously after
        /// insertion), so the original `DispatchQueue.main.async`
        /// approach read a stale flatten map or produced a block path
        /// whose id didn't match the freshly-parsed document — both
        /// caused `refreshSlashFilterEffect` to dismiss the palette
        /// immediately. Detecting in `textViewDidChange` after the
        /// parse-back guarantees consistency.
        var pendingSlashLocation: Int? = nil

        /// UTF-16 offset of the `/` that opened the currently-
        /// presented palette. Set in `textViewDidChange` (typed `/`
        /// path) and via the `onEditorCommand` interception in
        /// `makeUIView` (⌘⇧/ keyboard shortcut path). Cleared in
        /// `updateUIView` when `isSlashPaletteOpen` flips to false.
        /// `scrollViewDidScroll` reads this to republish the rect
        /// so the popover anchor tracks the slash glyph through
        /// scroll without us having to observe scroll position
        /// in the wiring view.
        var pinnedSlashLocation: Int? = nil

        init(parent: TextKitEditorView) {
            self.parent = parent
            self.lastSyncedDocument = parent.document
            super.init()
        }

        // MARK: - Document sync (imperative boundary, EDD §22.4.1)

        /// Parse the storage into a document, rebuild the bridging
        /// indexes, and push the result through the binding. The ONE
        /// place storage → document flows. Sets `lastSyncedDocument`
        /// BEFORE pushing so `updateUIView`'s reconciliation never
        /// wholesale-replaces in response to our own push.
        func syncDocumentFromStorage(_ textView: UITextView) {
            cancelPendingSync()
            let parsed = TextKitEditorView.parseBack(textView.attributedText)
            pathIndex = TextKitEditorView.leafPathIndex(parsed)
            let rebuilt = TextKitEditorView.maps(
                fromStorage: textView.attributedText,
                pathIndex: pathIndex
            )
            flattenMap = rebuilt.flattenMap
            flattenIDMap = rebuilt.flattenIDMap
            lastNewlineCount = TextKitEditorView.newlineCount(in: textView.text as NSString)
            lastSyncedDocument = parsed
            if parsed != parent.document {
                parent.document = parsed
            }
            // Re-mirror the selection AFTER the document: identity
            // hygiene can reassign the caret paragraph's blockID
            // (fresh id on the new line after Enter) WITHOUT a
            // selection change, leaving the reducer's selection
            // naming the OLD block. updateUIView's semantic gate
            // would then "correct" the caret back to the old
            // paragraph — the caret-jumps-to-previous-line bug.
            // Bridging against the freshly rebuilt pathIndex keeps
            // the reducer's mirror agreeing with storage identity.
            let bridged = TextKitEditorView.bridgeSelection(
                storage: textView.attributedText,
                selectedRange: textView.selectedRange,
                pathIndex: pathIndex
            )
            if bridged != parent.selection {
                parent.selection = bridged
            }
        }

        /// Typing path: defer the parse until the user pauses. The
        /// reducer's own persist debounce stacks on top, so a save
        /// lands ~idle + 600ms after the last keystroke — same order
        /// of magnitude as before, without the per-keystroke
        /// full-document parse + throwaway re-flatten.
        func scheduleDebouncedSync(_ textView: UITextView) {
            syncTask?.cancel()
            syncTask = Task { [weak self, weak textView] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, let textView else { return }
                self.syncDocumentFromStorage(textView)
            }
        }

        func cancelPendingSync() {
            syncTask?.cancel()
            syncTask = nil
        }

        /// True while a debounced sync is pending — the teardown path
        /// uses this to decide whether a final flush is needed.
        var hasPendingSync: Bool { syncTask != nil }

        // MARK: - Storage surgery primitives

        /// Replace characters in the storage, registering a
        /// self-inverting undo operation (undo restores the prior
        /// attributed substring; redo re-registers symmetrically) and
        /// re-syncing the document after each undo/redo application
        /// so the reducer's mirror follows the storage.
        func replaceCharactersRegisteringUndo(
            in textView: UITextView,
            range: NSRange,
            with replacement: NSAttributedString
        ) {
            let storage = textView.textStorage
            guard range.location + range.length <= storage.length else { return }
            let before = storage.attributedSubstring(from: range)
            storage.replaceCharacters(in: range, with: replacement)
            let newRange = NSRange(location: range.location, length: replacement.length)
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                guard let tv = coordinator.textView else { return }
                coordinator.replaceCharactersRegisteringUndo(in: tv, range: newRange, with: before)
                coordinator.syncDocumentFromStorage(tv)
            }
        }

        /// Toggle an inline format across the current selection as
        /// paragraph-local storage surgery: parse the host paragraph's
        /// runs, apply the SAME tested mark logic the reducer uses
        /// (`TextEditingFeature.applyMarkToInlineRuns`), rebuild the
        /// paragraph through the SAME attribute composer flatten uses
        /// (`paragraphContent`), and swap it in with undo registered.
        /// Text length is unchanged, so the selection restores
        /// verbatim. Contract parity with the reducer path:
        /// insertion-point selections no-op; code blocks ignore
        /// inline formats; multi-paragraph selections clamp to the
        /// host paragraph (fix S2).
        func applyInlineToggle(_ format: TextEditingFeature.InlineFormat) {
            guard let textView = self.textView,
                  textView.markedTextRange == nil else { return }
            let sel = textView.selectedRange
            guard sel.length > 0 else { return }
            let storage: NSTextStorage = textView.textStorage

            let (paraRange, probe) = TextKitEditorView.paragraphSlice(at: sel.location, in: storage)
            guard paraRange.length > 0, let probe, probe < storage.length else { return }
            let attrs = storage.attributes(at: probe, effectiveRange: nil)
            guard let chromeRaw = attrs[.blockChrome] as? Int,
                  let chrome = BlockChrome(rawValue: chromeRaw),
                  chrome != .codeBlock, chrome != .divider,
                  let blockID = attrs[.blockID] as? UUID else { return }

            let runs = TextKitEditorView.parseInlineRuns(
                attributed: storage,
                range: paraRange,
                chrome: chrome
            )
            let clampedEnd = min(sel.location + sel.length, paraRange.location + paraRange.length)
            let (rebuilt, _) = TextEditingFeature.applyMarkToInlineRuns(
                runs: runs,
                mark: TextEditingFeature.mark(for: format),
                startUTF16: sel.location - paraRange.location,
                endUTF16: clampedEnd - paraRange.location
            )
            let replacement = TextKitEditorView.paragraphContent(
                runs: rebuilt,
                chrome: chrome,
                blockID: blockID,
                groupID: attrs[.groupID] as? UUID,
                languageHint: attrs[.fromInkLanguageHint] as? String,
                listItemID: attrs[.fromInkListItemID] as? UUID,
                bodyFont: parent.bodyFont,
                bodyColor: parent.bodyColor
            )
            replaceCharactersRegisteringUndo(in: textView, range: paraRange, with: replacement)
            // Same text, new attributes — the original selection is
            // still valid (clamped to the paragraph like the bridge).
            textView.selectedRange = NSRange(
                location: sel.location,
                length: clampedEnd - sel.location
            )
            syncDocumentFromStorage(textView)
        }

        /// Apply the post-structural-edit identity fixups (fresh
        /// blockIDs on duplicate paragraphs, heading→body demotion,
        /// fresh ListItem ids) with undo registered per fixup —
        /// attribute restoration joins the native edit's undo group
        /// (same runloop), so ⌘Z of an Enter restores both the text
        /// AND the identity attributes.
        func applyParagraphIdentityFixups(_ textView: UITextView) {
            let storage: NSTextStorage = textView.textStorage
            let fixups = TextKitEditorView.paragraphIdentityFixups(in: storage)
            guard !fixups.isEmpty else { return }
            for fixup in fixups {
                let snapshotBefore = storage.attributedSubstring(from: fixup.range)
                storage.addAttribute(.blockID, value: fixup.freshBlockID, range: fixup.range)
                if let freshItemID = fixup.freshListItemID {
                    storage.addAttribute(.fromInkListItemID, value: freshItemID, range: fixup.range)
                }
                if fixup.demoteToParagraph {
                    demoteToBodyParagraph(storage: storage, range: fixup.range)
                }
                registerAttributeRestore(
                    snapshotBefore,
                    at: fixup.range.location,
                    in: textView
                )
            }
            // The caret usually sits inside a just-fixed paragraph —
            // refresh typingAttributes so the next keystroke inherits
            // the fixed identity, not the pre-split one.
            TextKitEditorView.refreshTypingAttributes(
                textView: textView,
                document: lastSyncedDocument,
                selection: parent.selection,
                bodyFont: parent.bodyFont,
                bodyColor: parent.bodyColor
            )
        }

        /// Demote a heading paragraph to body chrome in place: chrome
        /// + paragraph style + per-run font retargeting that preserves
        /// bold/italic traits (inline marks survive the demotion, the
        /// heading typography doesn't).
        private func demoteToBodyParagraph(storage: NSTextStorage, range: NSRange) {
            storage.addAttribute(.blockChrome, value: BlockChrome.paragraph.rawValue, range: range)
            storage.addAttribute(
                .paragraphStyle,
                value: TextKitEditorView.paragraphStyle(for: .paragraph),
                range: range
            )
            let bodyFont = parent.bodyFont
            storage.enumerateAttribute(.font, in: range, options: []) { value, runRange, _ in
                guard let oldFont = value as? UIFont else {
                    storage.addAttribute(.font, value: bodyFont, range: runRange)
                    return
                }
                let oldTraits = oldFont.fontDescriptor.symbolicTraits
                var newTraits = bodyFont.fontDescriptor.symbolicTraits
                if oldTraits.contains(.traitBold) { newTraits.insert(.traitBold) }
                if oldTraits.contains(.traitItalic) { newTraits.insert(.traitItalic) }
                let retargeted = bodyFont.fontDescriptor.withSymbolicTraits(newTraits)
                    .map { UIFont(descriptor: $0, size: 0) } ?? bodyFont
                storage.addAttribute(.font, value: retargeted, range: runRange)
            }
        }

        /// Register a self-inverting attribute-restore undo op: undo
        /// re-applies `snapshot`'s attributes over the same range and
        /// registers the inverse again so redo works symmetrically.
        private func registerAttributeRestore(
            _ snapshot: NSAttributedString,
            at location: Int,
            in textView: UITextView
        ) {
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                guard let tv = coordinator.textView else { return }
                let storage = tv.textStorage
                let range = NSRange(location: location, length: snapshot.length)
                guard range.location + range.length <= storage.length else { return }
                let current = storage.attributedSubstring(from: range)
                snapshot.enumerateAttributes(
                    in: NSRange(location: 0, length: snapshot.length),
                    options: []
                ) { attrs, runRange, _ in
                    storage.setAttributes(
                        attrs,
                        range: NSRange(location: location + runRange.location, length: runRange.length)
                    )
                }
                coordinator.registerAttributeRestore(current, at: location, in: tv)
                coordinator.syncDocumentFromStorage(tv)
            }
        }

        // MARK: - UITextViewDelegate

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // Marked text active (CJK composition, dictation
            // mid-utterance) — the input system owns the buffer.
            // No slash arming and, critically, no Enter interception:
            // Return during composition COMMITS the composition, and
            // routing it through the reducer (which re-flattens and
            // replaces `attributedText`) would destroy the marked-
            // text session. Let UIKit handle everything; the
            // document re-syncs from `textViewDidChange` once the
            // composition ends.
            if textView.markedTextRange != nil {
                pendingSlashLocation = nil
                return true
            }

            // Last-line defense for the disappearing-bullet bug:
            // UIKit strips the custom keys from typingAttributes on
            // every selection change, and delegate dispatch order
            // isn't guaranteed to let textViewDidChangeSelection's
            // re-assertion win. shouldChangeTextIn fires immediately
            // before the input system applies this change — merging
            // here guarantees the inserted text carries the host
            // paragraph's chrome/identity keys.
            textView.typingAttributes = TextKitEditorView.typingAttributesPreservingChrome(
                derived: textView.typingAttributes,
                storage: textView.attributedText,
                caretLocation: range.location,
                bodyFont: parent.bodyFont,
                bodyColor: parent.bodyColor
            )

            switch TextKitEditorView.evaluateSlashTrigger(
                replacementText: text,
                replacementRange: range,
                currentText: textView.text ?? ""
            ) {
            case .armed(let location):
                pendingSlashLocation = location
            case .clear:
                pendingSlashLocation = nil
            }

            // Empty-list-item Enter → exit the list. The exit goes
            // through the reducer (cold path); we suppress the
            // newline so the user never sees a fleeting extra empty
            // item before the format flips. Emptiness + chrome are
            // read from the STORAGE (always fresh) rather than the
            // debounce-stale document, and the document is synced
            // first so the reducer's surgery starts from current
            // content.
            if TextKitEditorView.shouldExitList(
                replacementText: text,
                replacementRange: range,
                storage: textView.attributedText
            ) {
                pendingSlashLocation = nil
                syncDocumentFromStorage(textView)
                parent.onCommand(.exitList)
                return false
            }

            // Every other Enter is UIKit-native (imperative boundary,
            // EDD §22.4.1): the input system inserts the newline —
            // undo-registered, IME-safe, marks split correctly by
            // attribute continuation — and `textViewDidChange`'s
            // structural path assigns the new paragraph its identity
            // (fresh blockID, heading demotion) before the immediate
            // document sync.
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingBindingUpdate else {
                // Programmatic re-apply is in flight. Don't consume a
                // pending slash here — wait for the next genuine
                // user-driven didChange. But DON'T clear pending
                // either: the next didChange will validate before
                // firing (see consume block below), so a stale flag
                // can't fire spuriously.
                return
            }
            // Composition in flight — don't parse provisional marked
            // text into the document (it would persist half-composed
            // CJK input and push a binding update whose re-flatten
            // could destroy the composition). The commit fires a
            // final didChange with `markedTextRange == nil`, which
            // re-syncs everything below.
            guard textView.markedTextRange == nil else { return }

            // Structural change? (Enter, paste with newlines,
            // cross-paragraph delete.) Paragraph identity must be
            // fixed up and the document synced NOW — selection
            // bridging and reducer surgery depend on fresh structure.
            // Plain typing schedules a debounced sync instead: no
            // full-document parse, no throwaway re-flatten, per
            // keystroke (EDD §22.4.1).
            let newlines = TextKitEditorView.newlineCount(in: textView.text as NSString)
            let isStructural = newlines != lastNewlineCount
            // Typing past the final `\n` mints a new paragraph
            // without moving the newline count — same identity
            // problem, same fixups.
            let needsTailFixup = !isStructural
                && TextKitEditorView.tailParagraphNeedsIdentityFixup(in: textView.attributedText)
            if isStructural || needsTailFixup {
                applyParagraphIdentityFixups(textView)
            }

            // While the palette is open (or a trigger is pending),
            // every keystroke syncs immediately — a palette command
            // is a reducer-driven mutation, and the reducer must
            // never act on a document missing the last few hundred
            // ms of typing.
            let paletteInteraction = pinnedSlashLocation != nil || pendingSlashLocation != nil
            if isStructural || needsTailFixup || paletteInteraction {
                syncDocumentFromStorage(textView)
            } else {
                scheduleDebouncedSync(textView)
            }

            // Live filter republish while the palette is open —
            // computed storage-side; nil dismisses (trigger deleted).
            if let pinned = pinnedSlashLocation {
                parent.onSlashFilterChanged(
                    TextKitEditorView.slashFilter(
                        storage: textView.attributedText,
                        triggerLocation: pinned
                    )
                )
            }

            // Consume any pending slash trigger from shouldChangeTextIn.
            // Validate first: the character at slashLocation must be
            // a `/` in the current text — defends against any state
            // shift between shouldChange and the consume (e.g. paste,
            // autocorrect, programmatic edit).
            guard let slashLocation = pendingSlashLocation else { return }
            pendingSlashLocation = nil
            guard let attributedText = textView.attributedText,
                  slashLocation < attributedText.length else { return }
            let charRange = NSRange(location: slashLocation, length: 1)
            let char = (attributedText.string as NSString).substring(with: charRange)
            guard char == "/" else { return }

            let bridged = TextKitEditorView.bridgeSelection(
                storage: attributedText,
                selectedRange: NSRange(location: slashLocation, length: 0),
                pathIndex: pathIndex
            )
            guard !bridged.path.isEmpty else { return }

            // Caret rect at the SLASH position, not the current
            // cursor (which has advanced by one after the insertion).
            // This keeps the popover pinned to the slash glyph while
            // the user types filter characters after it.
            let caretRect = TextKitEditorView.visibleCaretRect(
                in: textView,
                atOffset: slashLocation
            )

            // Pin the location for scroll tracking — scroll events
            // (see `scrollViewDidScroll`) republish a fresh rect so
            // the popover follows the slash glyph as the user
            // scrolls. Cleared in `updateUIView` when the palette
            // closes.
            self.pinnedSlashLocation = slashLocation

            parent.onSlashTyped(bridged.path, bridged.startUTF16, caretRect)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Keyboard dismissal / focus loss — flush any pending
            // debounced sync so the reducer's flush-on-disappear
            // persists current content, not content minus the last
            // few hundred ms of typing.
            if hasPendingSync {
                syncDocumentFromStorage(textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Phantom-position clamp. Flatten terminates EVERY
            // paragraph with `\n`, so TextKit exposes a tappable
            // extra-line-fragment position AFTER the final newline —
            // a position that addresses no paragraph: the selection
            // bridge returns unset, exitList no-ops, and Return there
            // appends rows it inherits attrs for, endlessly. The
            // caret must never rest there; snap it to `length - 1`,
            // the end of the last REAL paragraph (Apple Notes does
            // the equivalent — tapping below the last line lands at
            // its end). Re-setting selectedRange re-enters this
            // delegate once with a non-phantom position.
            let storageLength = textView.attributedText.length
            if textView.selectedRange.length == 0,
               textView.selectedRange.location == storageLength,
               storageLength > 0,
               (textView.attributedText.string as NSString).character(at: storageLength - 1) == 0x0A {
                textView.selectedRange = NSRange(location: storageLength - 1, length: 0)
                return
            }

            // UIKit just re-derived typingAttributes for the new
            // caret position and STRIPPED every custom key (verified
            // 2026-06-10 — see typingAttributesPreservingChrome).
            // Re-assert the chrome/identity keys on every selection
            // change, including programmatic ones, or the next typed
            // character lands chromeless and the block's bullet /
            // number / quote chrome vanishes.
            textView.typingAttributes = TextKitEditorView.typingAttributesPreservingChrome(
                derived: textView.typingAttributes,
                storage: textView.attributedText,
                caretLocation: textView.selectedRange.location,
                bodyFont: parent.bodyFont,
                bodyColor: parent.bodyColor
            )

            guard !isApplyingBindingUpdate else { return }
            // Attribute-based bridge: O(paragraph) against the live
            // storage. The flatten maps are only rebuilt at sync
            // points and their offsets go stale between keystrokes —
            // the bridge never does.
            let bridged = TextKitEditorView.bridgeSelection(
                storage: textView.attributedText,
                selectedRange: textView.selectedRange,
                pathIndex: pathIndex
            )
            if bridged != parent.selection {
                parent.selection = bridged
            }
        }

        // MARK: - UIScrollViewDelegate

        /// `UITextViewDelegate` inherits from `UIScrollViewDelegate`
        /// — UIKit invokes this on every scroll tick (touch drag,
        /// momentum, programmatic scroll-to-caret). While the
        /// palette is open we republish the slash glyph's current
        /// viewport rect so the popover anchor follows the slash
        /// instead of drifting away as the textView scrolls. When
        /// the palette closes, `pinnedSlashLocation` is nil and we
        /// skip — no allocation overhead during ordinary scrolling.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = self.textView,
                  let location = pinnedSlashLocation else { return }
            let rect = TextKitEditorView.visibleCaretRect(
                in: textView,
                atOffset: location
            )
            parent.onCaretAnchorMoved(rect)
        }
    }
}

// MARK: - BlockTreeTextView (UITextView subclass with key commands)

/// `UITextView` subclass that surfaces a fixed `keyCommands`
/// vocabulary for inline + block formats + slash palette + lists.
/// See `EditorCommand` doc for the full shortcut table.
///
/// **Why a subclass?** UITextView itself doesn't expose
/// `inputAccessoryView`-friendly key commands above its own built-in
/// editing shortcuts. Overriding `keyCommands` on a subclass is the
/// supported path. The subclass routes each command via the
/// `onEditorCommand` closure so the SwiftUI / TCA layer can dispatch
/// without the subclass knowing anything about the feature.
///
/// **Method visibility.** The selector-target methods are `internal`
/// (no explicit modifier) so the test file in the same module can
/// reference them via `#selector(...)` — selector-name strings via
/// `NSSelectorFromString` would be brittle to renames; the
/// compiler-checked `#selector` form catches typos. `fileprivate`
/// would scope them to this file only and break cross-file selector
/// usage from tests.
final class BlockTreeTextView: UITextView {
    /// Closure the editor wiring sets to route each command. Nil
    /// during initial layout / dealloc — the action methods below
    /// guard for that.
    var onEditorCommand: ((EditorCommand) -> Void)? = nil

    /// Cached `keyCommands` array (M1). UIKit calls the getter
    /// periodically while the responder chain is walked or when ⌘ is
    /// held to bring up the iPadOS HUD. Building 12 `UIKeyCommand`s
    /// each call wastes allocation cycles; building once at first
    /// access amortizes the cost. Lazy var rather than a static
    /// constant because `UIKeyCommand` is a class — UIKit mutates
    /// internal state on each instance (key-repeat tracking, etc.)
    /// so cross-instance sharing isn't safe.
    private lazy var cachedKeyCommands: [UIKeyCommand] = Self.buildKeyCommands()

    override var keyCommands: [UIKeyCommand]? { cachedKeyCommands }

    private static func buildKeyCommands() -> [UIKeyCommand] {
        // Each command's `wantsPriorityOverSystemBehavior` is true so
        // our bindings trump UITextView's defaults (the relevant
        // collisions are ⌘B/I/U which UITextView would otherwise
        // interpret through its own rich-text path).
        //
        // `discoverabilityTitle` has been available since iOS 9 and
        // shows in the hold-⌘ HUD on iPad with hardware keyboards.
        let entries: [(input: String, mods: UIKeyModifierFlags, action: Selector, title: String)] = [
            ("b",  .command,                        #selector(formatBold(_:)),          "Bold"),
            ("i",  .command,                        #selector(formatItalic(_:)),        "Italic"),
            ("u",  .command,                        #selector(formatUnderline(_:)),     "Underline"),
            ("x",  [.command, .shift],              #selector(formatStrikethrough(_:)), "Strikethrough"),
            ("e",  .command,                        #selector(formatCode(_:)),          "Code"),
            ("1",  [.command, .alternate],          #selector(applyHeading1(_:)),       "Heading 1"),
            ("2",  [.command, .alternate],          #selector(applyHeading2(_:)),       "Heading 2"),
            ("3",  [.command, .alternate],          #selector(applyHeading3(_:)),       "Heading 3"),
            ("0",  [.command, .alternate],          #selector(applyBodyParagraph(_:)),  "Body"),
            ("7",  [.command, .shift],              #selector(applyNumberedList(_:)),   "Numbered List"),
            ("8",  [.command, .shift],              #selector(applyBulletedList(_:)),   "Bulleted List"),
            ("/",  [.command, .shift],              #selector(openSlashPalette(_:)),    "Slash Menu"),
        ]
        return entries.map { entry in
            let cmd = UIKeyCommand(input: entry.input, modifierFlags: entry.mods, action: entry.action)
            cmd.wantsPriorityOverSystemBehavior = true
            cmd.discoverabilityTitle = entry.title
            return cmd
        }
    }

    @objc func formatBold(_ sender: Any?) { onEditorCommand?(.toggleBold) }
    @objc func formatItalic(_ sender: Any?) { onEditorCommand?(.toggleItalic) }
    @objc func formatUnderline(_ sender: Any?) { onEditorCommand?(.toggleUnderline) }
    @objc func formatStrikethrough(_ sender: Any?) { onEditorCommand?(.toggleStrikethrough) }
    @objc func formatCode(_ sender: Any?) { onEditorCommand?(.toggleCode) }
    @objc func applyHeading1(_ sender: Any?) { onEditorCommand?(.applyHeading(level: 1)) }
    @objc func applyHeading2(_ sender: Any?) { onEditorCommand?(.applyHeading(level: 2)) }
    @objc func applyHeading3(_ sender: Any?) { onEditorCommand?(.applyHeading(level: 3)) }
    @objc func applyBodyParagraph(_ sender: Any?) { onEditorCommand?(.applyBody) }
    @objc func applyBulletedList(_ sender: Any?) { onEditorCommand?(.applyBulletedList) }
    @objc func applyNumberedList(_ sender: Any?) { onEditorCommand?(.applyNumberedList) }
    @objc func openSlashPalette(_ sender: Any?) {
        // Capture the current caret rect so the wiring view can
        // anchor the popover beside the cursor. Subtract
        // `contentOffset` so the rect is in viewport space — the
        // same convention `TextKitEditorView.visibleCaretRect` uses
        // for the typed-slash path, so the wiring view treats both
        // sources identically.
        //
        // The `.zero` fallback is defensive: `UIKeyCommand` only
        // dispatches while this view is in the responder chain,
        // which means `selectedTextRange` is non-nil in practice.
        // Cheap insurance against a UIKit edge case.
        let rect: CGRect
        if let start = selectedTextRange?.start {
            rect = caretRect(for: start)
                .offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
        } else {
            rect = .zero
        }
        onEditorCommand?(.openSlashPalette(caretRectInEditor: rect))
    }
}

// MARK: - BlockChrome — paragraph-level discriminator

/// Discriminator the `BlockDecoratingLayoutManager` reads off each
/// paragraph's `.blockChrome` attribute. Determines which (if any)
/// background chrome to draw, and what typography the paragraph
/// uses.
enum BlockChrome: Int {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletListItem
    case orderedListItem
    case blockquoteParagraph
    case codeBlock
    case divider
}

extension NSAttributedString.Key {
    /// `Int` rawValue of `BlockChrome`. Set on every character of a
    /// flattened paragraph (including its trailing newline). The
    /// layout manager reads this to decide whether to draw a
    /// blockquote bar, code tint, divider rule, or list marker.
    static let blockChrome = NSAttributedString.Key("fromInk.blockChrome")

    /// UUID of the source `Block`. The parse-back path uses this to
    /// preserve block IDs across edits where possible. New paragraphs
    /// from Enter get a fresh UUID at parse-back time, and the
    /// parse-back path dedupes collisions (Enter inherits the prior
    /// paragraph's blockID via typingAttributes — the duplicate gets
    /// a fresh UUID).
    static let blockID = NSAttributedString.Key("fromInk.blockID")

    /// Shared identifier for paragraphs that belong to the same
    /// parent container (bulletList items, orderedList items,
    /// blockquote children). The parse-back groups consecutive
    /// paragraphs with the SAME `groupID` AND the same chrome into a
    /// single container block.
    static let groupID = NSAttributedString.Key("fromInk.groupID")

    /// `HighlightKind.rawValue` (a `String`) for inline runs that
    /// carry a `Mark.highlight(_)`. Set alongside `.backgroundColor`
    /// during flatten — the background color produces the visual
    /// emphasis; this key carries the semantic kind so parse-back
    /// recovers the exact Mark case instead of inferring from the
    /// color (which is impossible without bijective color → kind
    /// mapping). Without this key, parse-back would silently drop the
    /// highlight on the first edit.
    static let fromInkHighlightKind = NSAttributedString.Key("fromInk.highlightKind")

    /// `true` for inline runs that carry `Mark.code`. Set alongside
    /// the monospaced font + tinted background during flatten so the
    /// parse-back can distinguish "code mark" from "happens to have a
    /// monospaced font for an unrelated reason."
    static let fromInkInlineCode = NSAttributedString.Key("fromInk.inlineCode")

    /// Optional `String` language hint for `codeBlock` blocks. Set on
    /// the paragraph attributes of a code-block leaf during flatten;
    /// recovered by parse-back into `Block.codeBlock(languageHint:)`.
    static let fromInkLanguageHint = NSAttributedString.Key("fromInk.languageHint")

    /// `UUID` of the source `ListItem` that this paragraph belongs to,
    /// for list-item identity preservation across round-trips.
    /// Currently unused by parse-back (which rebuilds list items with
    /// fresh ids) but flattened for future use.
    static let fromInkListItemID = NSAttributedString.Key("fromInk.listItemID")
}

// MARK: - BlockDecoratingLayoutManager

/// `NSLayoutManager` subclass that draws block-level chrome via
/// `drawBackground(forGlyphRange:at:)`. Only TextKit 1 invokes this
/// override — see the type doc on `TextKitEditorView` for the full
/// architectural rationale.
final class BlockDecoratingLayoutManager: NSLayoutManager {
    var tintColor: UIColor = .label

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage = textStorage else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let nsString = textStorage.string as NSString
        let storageLength = textStorage.length

        // Enumerate by **paragraph boundary** (split on `\n`), not
        // by `.blockChrome` or `.blockID`. Both attribute-based
        // enumerations have a fatal flaw for live editing: when
        // the user types after pressing Enter, `typingAttributes`
        // carries the previous paragraph's chrome AND blockID
        // forward. UIKit applies those attrs to the new character,
        // so two adjacent paragraphs in `attributedText` carry
        // identical attribute values — `enumerateAttribute`
        // consolidates them into one range, and only the first
        // line gets a chrome paint. Splitting on `\n` instead
        // gives us one paint call per paragraph regardless of
        // attribute consolidation.
        let end = charRange.location + charRange.length
        var cursor = charRange.location
        while cursor < end {
            let searchRange = NSRange(location: cursor, length: end - cursor)
            let nlRange = nsString.range(of: "\n", options: [], range: searchRange)
            let paraEnd = nlRange.location != NSNotFound ? nlRange.location : end
            let paraRange = NSRange(location: cursor, length: paraEnd - cursor)

            // Probe chrome at the first character of the
            // paragraph, or at the trailing `\n` itself for empty
            // paragraphs (the `\n` carries the paragraph's attrs
            // because flatten sets them there too).
            let probeLocation: Int
            if paraRange.length > 0 {
                probeLocation = paraRange.location
            } else if paraEnd < storageLength {
                probeLocation = paraEnd
            } else if paraRange.location > 0 {
                probeLocation = paraRange.location - 1
            } else {
                probeLocation = -1
            }

            if probeLocation >= 0,
               probeLocation < storageLength,
               let chromeRaw = textStorage.attribute(.blockChrome, at: probeLocation, effectiveRange: nil) as? Int,
               let chrome = BlockChrome(rawValue: chromeRaw) {

                // Extend the glyph range by one when the paragraph
                // has no text — `enumerateLineFragments` doesn't
                // iterate over zero-length ranges, but the
                // trailing `\n` at `paraEnd` has its own line
                // fragment we can anchor against.
                let extendedChar: NSRange
                if paraRange.length == 0, paraEnd < storageLength {
                    extendedChar = NSRange(location: paraRange.location, length: 1)
                } else {
                    extendedChar = paraRange
                }
                let glyphRange = self.glyphRange(forCharacterRange: extendedChar, actualCharacterRange: nil)
                let probeRange = NSRange(location: probeLocation, length: 1)

                switch chrome {
                case .blockquoteParagraph:
                    drawBlockquote(glyphRange: glyphRange, origin: origin)
                case .codeBlock:
                    drawCodeBlock(glyphRange: glyphRange, origin: origin)
                case .divider:
                    drawDivider(glyphRange: glyphRange, origin: origin)
                case .bulletListItem:
                    drawBullet(glyphRange: glyphRange, origin: origin, storage: textStorage, charRange: probeRange)
                case .orderedListItem:
                    // The ordinal is derived from the item's position
                    // within its group in the STORAGE, not from a
                    // per-draw running counter. drawBackground is
                    // invoked with only the glyph range being redrawn
                    // — a counter that starts at the first *drawn*
                    // item renders item 11 as "1." the moment a long
                    // list is scrolled mid-way.
                    let groupID = textStorage.attribute(.groupID, at: probeLocation, effectiveRange: nil) as? UUID
                    let ordinal = Self.orderedItemOrdinal(
                        in: textStorage,
                        paragraphStart: paraRange.location,
                        groupID: groupID
                    )
                    drawNumber(ordinal, glyphRange: glyphRange, origin: origin, storage: textStorage, charRange: probeRange)
                default:
                    break
                }
            }

            if nlRange.location == NSNotFound { break }
            cursor = paraEnd + 1
        }
    }

    // MARK: - Ordered-list ordinal (pure, testable)

    /// 1-based ordinal of the ordered-list item whose paragraph starts
    /// at `paragraphStart`, computed by walking PRECEDING paragraphs in
    /// the storage while they carry the same `.groupID` and
    /// `.orderedListItem` chrome. Pure over the attributed string so it
    /// can be unit-tested against `flatten` output without a layout
    /// pass.
    ///
    /// The walk probes each preceding paragraph at its first character
    /// — or at its trailing `\n` for empty paragraphs, which carries
    /// the paragraph attrs per the flatten contract (and per
    /// `typingAttributes` for freshly typed lines).
    static func orderedItemOrdinal(
        in storage: NSAttributedString,
        paragraphStart: Int,
        groupID: UUID?
    ) -> Int {
        let nsString = storage.string as NSString
        var ordinal = 1
        var cursor = paragraphStart
        while cursor > 0 {
            // `cursor - 1` is the previous paragraph's terminating
            // `\n`. Find that paragraph's start.
            let searchRange = NSRange(location: 0, length: max(0, cursor - 1))
            let prevNL = nsString.range(of: "\n", options: .backwards, range: searchRange)
            let prevStart = prevNL.location != NSNotFound ? prevNL.location + 1 : 0
            // Probe at the paragraph start; an empty previous
            // paragraph's start IS its trailing newline, which
            // carries the paragraph attrs.
            guard prevStart < storage.length else { break }
            let attrs = storage.attributes(at: prevStart, effectiveRange: nil)
            let prevChrome = (attrs[.blockChrome] as? Int).flatMap(BlockChrome.init(rawValue:))
            let prevGroup = attrs[.groupID] as? UUID
            guard prevChrome == .orderedListItem, prevGroup == groupID else { break }
            ordinal += 1
            cursor = prevStart
        }
        return ordinal
    }

    // MARK: - Per-chrome drawing

    private func drawBlockquote(glyphRange: NSRange, origin: CGPoint) {
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, container, _, _ in
            let frag = usedRect.offsetBy(dx: origin.x, dy: origin.y)
            let inset = container.lineFragmentPadding
            let bg = CGRect(
                x: origin.x + inset,
                y: frag.minY,
                width: container.size.width - inset * 2,
                height: frag.height
            )
            UIColor.label.withAlphaComponent(0.04).setFill()
            UIBezierPath(rect: bg).fill()

            let bar = CGRect(
                x: origin.x + 6,
                y: frag.minY + 2,
                width: 3,
                height: frag.height - 4
            )
            UIColor.label.withAlphaComponent(0.4).setFill()
            UIBezierPath(rect: bar).fill()
        }
    }

    private func drawCodeBlock(glyphRange: NSRange, origin: CGPoint) {
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, container, _, _ in
            let frag = usedRect.offsetBy(dx: origin.x, dy: origin.y)
            let inset = container.lineFragmentPadding
            let bg = CGRect(
                x: origin.x + inset,
                y: frag.minY,
                width: container.size.width - inset * 2,
                height: frag.height
            )
            UIColor.label.withAlphaComponent(0.06).setFill()
            UIBezierPath(rect: bg).fill()
        }
    }

    private func drawDivider(glyphRange: NSRange, origin: CGPoint) {
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, container, _, _ in
            let frag = usedRect.offsetBy(dx: origin.x, dy: origin.y)
            let inset = container.lineFragmentPadding
            // 1pt horizontal rule at the vertical midpoint.
            let rule = CGRect(
                x: origin.x + inset,
                y: frag.midY - 0.5,
                width: container.size.width - inset * 2,
                height: 1
            )
            UIColor.label.withAlphaComponent(0.25).setFill()
            UIBezierPath(rect: rule).fill()
        }
    }

    /// Draw the leading list marker in the **indent space** (left
    /// of the text column), not inside the text column.
    ///
    /// `usedRect.minX` is where the glyphs start — that's `28` for
    /// list-item paragraphs (matching `firstLineHeadIndent`), so
    /// the old `usedRect.minX + 8` placed the bullet at x=36
    /// *inside* the text column, sitting under the first character.
    /// Using `lineFragmentRect.minX` instead gives the container's
    /// leading edge; adding `lineFragmentPadding + offset` puts the
    /// marker in the gutter the indent reserves for exactly this
    /// purpose. We enumerate (rather than calling a helper) so the
    /// closure receives both rects + the container in one pass.
    private func drawBullet(
        glyphRange: NSRange,
        origin: CGPoint,
        storage: NSTextStorage,
        charRange: NSRange
    ) {
        let bulletFont = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? UIFont
            ?? UIFont.preferredFont(forTextStyle: .body)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bulletFont,
            .foregroundColor: tintColor.withAlphaComponent(0.85)
        ]
        let bullet = NSAttributedString(string: "•", attributes: attrs)
        enumerateLineFragments(forGlyphRange: glyphRange) { lineFragRect, usedRect, container, _, stop in
            let x = origin.x + lineFragRect.minX + container.lineFragmentPadding + 10
            let y = origin.y + usedRect.minY
            bullet.draw(at: CGPoint(x: x, y: y))
            stop.pointee = true
        }
    }

    private func drawNumber(
        _ n: Int,
        glyphRange: NSRange,
        origin: CGPoint,
        storage: NSTextStorage,
        charRange: NSRange
    ) {
        let labelFont = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? UIFont
            ?? UIFont.preferredFont(forTextStyle: .body)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: tintColor.withAlphaComponent(0.85)
        ]
        let label = NSAttributedString(string: "\(n).", attributes: attrs)
        enumerateLineFragments(forGlyphRange: glyphRange) { lineFragRect, usedRect, container, _, stop in
            let x = origin.x + lineFragRect.minX + container.lineFragmentPadding + 4
            let y = origin.y + usedRect.minY
            label.draw(at: CGPoint(x: x, y: y))
            stop.pointee = true
        }
    }
}
#endif
