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
    let onSlashTyped: (_ blockPath: [UUID], _ offsetUTF16: Int) -> Void
    /// Routed from the custom UITextView subclass's `keyCommands` to
    /// the wiring view, which maps each `EditorCommand` onto a TCA
    /// action. The editor view stays feature-agnostic — it doesn't
    /// know about `TextEditingFeature.Action` names.
    let onCommand: (EditorCommand) -> Void
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
            coordinator?.parent.onCommand(command)
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
        // shape comparison triggers a re-flatten.
        if document != context.coordinator.lastSyncedDocument {
            let flattened = Self.flatten(
                document: document,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )
            context.coordinator.isApplyingBindingUpdate = true
            let priorSelection = textView.selectedRange
            textView.attributedText = flattened.attributed
            // Restore caret to a valid position (clamp).
            let clampedLocation = min(priorSelection.location, flattened.attributed.length)
            textView.selectedRange = NSRange(location: clampedLocation, length: 0)
            context.coordinator.flattenMap = flattened.flattenMap
            context.coordinator.flattenIDMap = flattened.flattenIDMap
            context.coordinator.lastSyncedDocument = document

            // Fix B3: refresh typingAttributes so the user's NEXT
            // keystroke inherits the chrome at the new cursor leaf.
            // Without this, a slash-command-applied heading would
            // revert to paragraph styling on the next character.
            Self.refreshTypingAttributes(
                textView: textView,
                bodyFont: bodyFont,
                bodyColor: bodyColor
            )

            context.coordinator.isApplyingBindingUpdate = false
        }

        // Selection re-sync.
        if let nsRange = Self.nsRange(
            for: selection,
            flattenIDMap: context.coordinator.flattenIDMap,
            totalLength: textView.attributedText.length
        ), nsRange != textView.selectedRange {
            context.coordinator.isApplyingBindingUpdate = true
            textView.selectedRange = nsRange
            context.coordinator.isApplyingBindingUpdate = false
        }
    }

    /// Read the chrome / blockID / groupID at the cursor's position
    /// in `textView.attributedText` and set `textView.typingAttributes`
    /// from them. Used after every external-document-driven re-flatten
    /// (B3) so format changes don't revert on the next keystroke.
    static func refreshTypingAttributes(
        textView: UITextView,
        bodyFont: UIFont,
        bodyColor: UIColor
    ) {
        let loc = textView.selectedRange.location
        guard loc < textView.attributedText.length else { return }
        let attrs = textView.attributedText.attributes(at: loc, effectiveRange: nil)
        guard let chromeRaw = attrs[.blockChrome] as? Int,
              let chrome = BlockChrome(rawValue: chromeRaw) else { return }
        let blockID = (attrs[.blockID] as? UUID) ?? UUID()
        let groupID = attrs[.groupID] as? UUID
        textView.typingAttributes = Self.typingAttributes(
            for: chrome,
            blockID: blockID,
            groupID: groupID,
            bodyFont: bodyFont,
            bodyColor: bodyColor
        )
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
        // Trim a trailing newline if any leaf added one.
        if mutable.length > 0,
           mutable.attributedSubstring(from: NSRange(location: mutable.length - 1, length: 1)).string == "\n" {
            mutable.deleteCharacters(in: NSRange(location: mutable.length - 1, length: 1))
        }
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

        // Build the paragraph text by concatenating inline runs.
        for run in runs {
            let runText = run.text
            let runAttributes: [NSAttributedString.Key: Any] = inlineAttributes(
                marks: run.marks,
                baseFont: font,
                baseColor: foreground
            )
            let runString = NSAttributedString(string: runText, attributes: runAttributes)
            mutable.append(runString)
        }
        // If the leaf had no runs (empty paragraph), append an empty
        // span to anchor the paragraph attributes.
        let paragraphText = mutable.string as NSString
        let paragraphLength = paragraphText.length - startLocation
        let paragraphRange = NSRange(location: startLocation, length: paragraphLength)

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
        mutable.enumerateAttributes(in: paragraphRange, options: []) { attrs, range, _ in
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

        init(parent: TextKitEditorView) {
            self.parent = parent
            self.lastSyncedDocument = parent.document
            super.init()
        }

        // MARK: - UITextViewDelegate

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
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
            let parsed = TextKitEditorView.parseBack(textView.attributedText)
            let reflatten = TextKitEditorView.flatten(
                document: parsed,
                bodyFont: parent.bodyFont,
                bodyColor: parent.bodyColor
            )
            self.flattenMap = reflatten.flattenMap
            self.flattenIDMap = reflatten.flattenIDMap
            self.lastSyncedDocument = parsed
            if parsed != parent.document {
                parent.document = parsed
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

            let bridged = TextKitEditorView.selection(
                forNSRange: NSRange(location: slashLocation, length: 0),
                flattenMap: reflatten.flattenMap
            )
            guard !bridged.path.isEmpty else { return }
            parent.onSlashTyped(bridged.path, bridged.startUTF16)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingBindingUpdate else { return }
            let bridged = TextKitEditorView.selection(
                forNSRange: textView.selectedRange,
                flattenMap: flattenMap
            )
            parent.selection = bridged
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
    @objc func openSlashPalette(_ sender: Any?) { onEditorCommand?(.openSlashPalette) }
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

        // Track consecutive listItem index for numbering.
        var orderedRunningNumber: [UUID: Int] = [:]

        textStorage.enumerateAttribute(.blockChrome, in: charRange, options: []) { value, range, _ in
            guard let raw = value as? Int, let chrome = BlockChrome(rawValue: raw) else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            switch chrome {
            case .blockquoteParagraph:
                drawBlockquote(glyphRange: glyphRange, origin: origin)
            case .codeBlock:
                drawCodeBlock(glyphRange: glyphRange, origin: origin)
            case .divider:
                drawDivider(glyphRange: glyphRange, origin: origin)
            case .bulletListItem:
                drawBullet(glyphRange: glyphRange, origin: origin, storage: textStorage, charRange: range)
            case .orderedListItem:
                let groupID = (textStorage.attribute(.groupID, at: range.location, effectiveRange: nil) as? UUID) ?? UUID()
                let next = (orderedRunningNumber[groupID] ?? 0) + 1
                orderedRunningNumber[groupID] = next
                drawNumber(next, glyphRange: glyphRange, origin: origin, storage: textStorage, charRange: range)
            default:
                break
            }
        }
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

    private func drawBullet(
        glyphRange: NSRange,
        origin: CGPoint,
        storage: NSTextStorage,
        charRange: NSRange
    ) {
        guard let firstLineFrag = self.firstLineFragmentRect(forGlyphRange: glyphRange) else { return }
        let frag = firstLineFrag.offsetBy(dx: origin.x, dy: origin.y)
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: tintColor.withAlphaComponent(0.85)
        ]
        let bullet = NSAttributedString(string: "•", attributes: bulletAttrs)
        bullet.draw(at: CGPoint(x: frag.minX + 8, y: frag.minY))
    }

    private func drawNumber(
        _ n: Int,
        glyphRange: NSRange,
        origin: CGPoint,
        storage: NSTextStorage,
        charRange: NSRange
    ) {
        guard let firstLineFrag = self.firstLineFragmentRect(forGlyphRange: glyphRange) else { return }
        let frag = firstLineFrag.offsetBy(dx: origin.x, dy: origin.y)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: tintColor.withAlphaComponent(0.85)
        ]
        let label = NSAttributedString(string: "\(n).", attributes: attrs)
        label.draw(at: CGPoint(x: frag.minX + 4, y: frag.minY))
    }

    /// Returns the rect of the FIRST line fragment for the glyph
    /// range — used to position list markers at the leading edge of
    /// the first line of each item.
    private func firstLineFragmentRect(forGlyphRange glyphRange: NSRange) -> CGRect? {
        var firstFragRect: CGRect? = nil
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, stop in
            firstFragRect = usedRect
            stop.pointee = true
        }
        return firstFragRect
    }
}
#endif
