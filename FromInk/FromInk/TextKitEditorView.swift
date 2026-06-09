#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// TextKit 2-backed rich text editor.
///
/// SwiftUI's `TextEditor` on iOS 26 honors **inline** AttributedString
/// attributes (bold / italic / underline / strikethrough) but does NOT
/// paint **block-level** `PresentationIntent` — headings, lists,
/// blockQuote, codeBlock, and thematicBreak persist semantically but
/// render as plain prose. Manual testing (2026-06-09) confirmed
/// blockQuote and bulletedList silently produced no visible change.
///
/// The text experience EDD §4 line 49 anticipated this:
///
/// > If a load-bearing capability (custom attribute round-trip, caret
/// > rect for slash anchoring, selection-menu extension) fails the
/// > spike, fall back to a `UIViewRepresentable` wrapping `UITextView`
/// > over TextKit 2 — same data shape, more code.
///
/// This is that wrapper. `UITextView(usingTextLayoutManager: true)`
/// installs `NSTextLayoutManager` (TextKit 2), which renders block-
/// level intents natively — heading size, list markers, blockquote
/// indent, monospaced code paragraphs, thematic break hairline rule.
///
/// **The Model surface** matches the prior TextEditor: a body
/// `AttributedString` binding, a selection `AttributedTextSelection`
/// binding, font / foreground / placeholder typography. `TextBlockView`
/// swaps `TextEditor` for `TextKitEditorView` with no other changes to
/// the Model, adapter, or wiring view.
///
/// **AttributedString ↔ NSAttributedString.** UITextView holds an
/// `NSAttributedString` internally. We convert in both directions
/// `including: \.fromInk` so the FromInkAttributes scope (region
/// anchors, highlights, slash-insertion markers) plus
/// `PresentationIntent` round-trip without loss. Verified via spike:
/// `NSAttributedString(attr, including: \.fromInk)` produces
/// `NSPresentationIntent` + `fromink.regionAnchor` keys on the
/// resulting NSAttributedString; the reverse recovers the typed
/// values.
///
/// **Feedback-loop guards.** Three sources of state change can
/// collide: SwiftUI pushes a new body via binding update → updateUIView
/// runs → sets `textView.attributedText`. UITextView's user input
/// fires `textViewDidChange` → coordinator pushes back to binding.
/// Without guards these loop. We:
///
///   1. Compare incoming `attributedText` against current before
///      assignment — skip if equal (avoids cursor jump).
///   2. Set `isApplyingBindingUpdate = true` during programmatic
///      assignment so the delegate's `textViewDidChange` short-
///      circuits the round-trip.
///
/// **Selection bridging.** UITextView exposes `selectedRange: NSRange`
/// over UTF-16 code units. `AttributedTextSelection` is index-based
/// over `AttributedString.Index`. We convert via the UTF-16 view —
/// stable across Swift's character-cluster reshuffles and matches
/// what UITextView reports natively.
@MainActor
struct TextKitEditorView: UIViewRepresentable {
    @Binding var body: AttributedString
    @Binding var selection: AttributedTextSelection
    let font: UIFont
    let foregroundColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 2 — without `usingTextLayoutManager: true`, UITextView
        // falls back to TextKit 1 (NSLayoutManager) and we lose the
        // built-in PresentationIntent rendering this whole view exists
        // to get.
        let textView = UITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = foregroundColor
        textView.backgroundColor = .clear
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        // No internal padding around the text container — the
        // wrapping view supplies the editorial margins.
        textView.textContainer.lineFragmentPadding = 0
        // Keep system spell-check / autocorrect on; matches Notes /
        // Bear default editor feel.
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        // Apply the initial body.
        let ns = Self.makeNSAttributedString(from: body, defaultFont: font, defaultColor: foregroundColor)
        textView.attributedText = ns
        // Seed selection if non-default.
        if let range = Self.nsRange(from: selection, in: body) {
            textView.selectedRange = range
        }
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        // Body re-sync — only when the SwiftUI side diverges from
        // what UITextView already shows. Comparing converted
        // NSAttributedStrings is the cheapest way to verify equality
        // because the strings already share the same encoding pass.
        let incoming = Self.makeNSAttributedString(
            from: body,
            defaultFont: font,
            defaultColor: foregroundColor
        )
        if !(textView.attributedText?.isEqual(to: incoming) ?? false) {
            context.coordinator.isApplyingBindingUpdate = true
            let priorSelection = textView.selectedRange
            textView.attributedText = incoming
            // Restore selection — assigning attributedText resets it
            // to NSRange(location: 0, length: 0) by default.
            let bounded = NSRange(
                location: min(priorSelection.location, incoming.length),
                length: 0
            )
            textView.selectedRange = bounded
            context.coordinator.isApplyingBindingUpdate = false
        }

        // Selection re-sync — when the reducer's `selection` state
        // diverges from UITextView's selectedRange (e.g. after
        // `bodyEdited` + `selectionChanged` actions that move the
        // caret programmatically). Same equality guard.
        if let target = Self.nsRange(from: selection, in: body),
           target != textView.selectedRange {
            context.coordinator.isApplyingBindingUpdate = true
            textView.selectedRange = target
            context.coordinator.isApplyingBindingUpdate = false
        }

        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != foregroundColor {
            textView.textColor = foregroundColor
        }
    }

    // MARK: - Conversion helpers

    /// Convert an `AttributedString` to `NSAttributedString` while
    /// preserving the `FromInkAttributes` scope (region anchors,
    /// highlights, slash-insertion markers) and standard scopes
    /// (`PresentationIntent`, `InlinePresentationIntent`,
    /// `underlineStyle`, font / color). Falls back to a plain
    /// NSAttributedString if conversion throws.
    ///
    /// Default font / color are applied as a base layer so plain
    /// stretches inherit the editor's typography.
    static func makeNSAttributedString(
        from attributed: AttributedString,
        defaultFont: UIFont,
        defaultColor: UIColor
    ) -> NSAttributedString {
        let converted: NSAttributedString
        do {
            converted = try NSAttributedString(attributed, including: \.fromInk)
        } catch {
            return NSAttributedString(string: String(attributed.characters), attributes: [
                .font: defaultFont,
                .foregroundColor: defaultColor
            ])
        }
        // Wrap the conversion in a mutable copy so we can apply the
        // default font/color underneath any explicit per-run font.
        // Per-run attributes (e.g. inline bold from
        // InlinePresentationIntent) override the base.
        let mutable = NSMutableAttributedString(attributedString: converted)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            if attrs[.font] == nil {
                mutable.addAttribute(.font, value: defaultFont, range: range)
            }
            if attrs[.foregroundColor] == nil {
                mutable.addAttribute(.foregroundColor, value: defaultColor, range: range)
            }
        }

        // PresentationIntent is a semantic attribute — TextKit 2
        // round-trips and serializes it but never paints it. To make
        // headings look like headings, lists like lists, blockquotes
        // like blockquotes, etc., we walk the intent and translate
        // it into concrete visual attributes (font, paragraph style,
        // color) that UITextView's text layout actually renders.
        // This is what every native-feeling rich text editor on iOS
        // does — Notes, Bear, Things — there's no "automatic" path.
        applyPresentationStyling(to: mutable, defaultFont: defaultFont, defaultColor: defaultColor)

        return mutable
    }

    /// Walk every paragraph that carries a `PresentationIntent` and
    /// apply the visual attributes UITextView actually renders. The
    /// intent itself stays on the attributed string so persistence
    /// continues to round-trip the semantic structure unchanged.
    private static func applyPresentationStyling(
        to mutable: NSMutableAttributedString,
        defaultFont: UIFont,
        defaultColor: UIColor
    ) {
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(
            .presentationIntentAttributeName,
            in: full,
            options: []
        ) { value, range, _ in
            guard let intent = value as? PresentationIntent, range.length > 0 else { return }
            let kinds = intent.components.map(\.kind)
            applyIntentVisuals(
                kinds: kinds,
                to: mutable,
                range: range,
                defaultFont: defaultFont,
                defaultColor: defaultColor
            )
        }
    }

    /// Translate a stack of PresentationIntent kinds (leaf first,
    /// container next) into NSAttributedString visual attributes
    /// over the given range. The visual choices match the editorial
    /// aesthetic in CLAUDE.md: New York serif for headings, the
    /// existing ink color tokens for accents, monospaced system for
    /// code, NSTextList markers for list items.
    private static func applyIntentVisuals(
        kinds: [PresentationIntent.Kind],
        to mutable: NSMutableAttributedString,
        range: NSRange,
        defaultFont: UIFont,
        defaultColor: UIColor
    ) {
        // Start with the defaults; each kind layered on top can
        // override font, paragraph style, foreground.
        var font: UIFont = defaultFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = 4
        paragraphStyle.paragraphSpacing = 4
        var foreground: UIColor = defaultColor
        var didApplyTextList = false

        for kind in kinds {
            switch kind {
            case .header(let level):
                let pointSize: CGFloat = level == 1 ? 28 : (level == 2 ? 22 : 18)
                let descriptor = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
                    .fontDescriptor
                    .withDesign(.serif) ?? UIFont.systemFont(ofSize: pointSize, weight: .semibold).fontDescriptor
                font = UIFont(descriptor: descriptor, size: 0)
                paragraphStyle.paragraphSpacingBefore = 8
                paragraphStyle.paragraphSpacing = 6

            case .blockQuote:
                if let italicDescriptor = defaultFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    font = UIFont(descriptor: italicDescriptor, size: 0)
                }
                paragraphStyle.firstLineHeadIndent = 20
                paragraphStyle.headIndent = 20
                paragraphStyle.paragraphSpacingBefore = 6
                paragraphStyle.paragraphSpacing = 6
                foreground = defaultColor.withAlphaComponent(0.7)

            case .codeBlock:
                font = UIFont.monospacedSystemFont(
                    ofSize: defaultFont.pointSize,
                    weight: .regular
                )
                paragraphStyle.firstLineHeadIndent = 12
                paragraphStyle.headIndent = 12

            case .listItem:
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.headIndent = 24
                // The marker attaches via NSTextList on the parent
                // kind below — set the indents here so the layout
                // is correct even if textLists ends up empty for any
                // reason.

            case .unorderedList:
                if !didApplyTextList {
                    paragraphStyle.textLists = [NSTextList(markerFormat: .disc, options: 0)]
                    didApplyTextList = true
                }

            case .orderedList:
                if !didApplyTextList {
                    paragraphStyle.textLists = [NSTextList(markerFormat: .decimal, options: 0)]
                    didApplyTextList = true
                }

            case .thematicBreak:
                // A divider paragraph. Replace the run's content
                // with a NSTextAttachment that draws a 1pt
                // horizontal rule across the available line width.
                // Drop this branch into the caller — the rendering
                // is more involved than a font/paragraph tweak.
                replaceWithRule(in: mutable, range: range, color: defaultColor)
                return

            default:
                break
            }
        }

        mutable.addAttribute(.font, value: font, range: range)
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        mutable.addAttribute(.foregroundColor, value: foreground, range: range)
    }

    /// Replace a thematic-break paragraph with a custom
    /// `NSTextAttachment` that paints a horizontal rule. UITextView
    /// has no native concept of a horizontal-line block, so the
    /// attachment is the only path that lays the rule out at the
    /// correct line-fragment width.
    private static func replaceWithRule(
        in mutable: NSMutableAttributedString,
        range: NSRange,
        color: UIColor
    ) {
        let attachment = HorizontalRuleAttachment(color: color.withAlphaComponent(0.35))
        let attrString = NSAttributedString(attachment: attachment)
        mutable.replaceCharacters(in: range, with: attrString)
    }

    /// Convert `NSAttributedString` back to `AttributedString`
    /// preserving the FromInkAttributes scope. On failure returns a
    /// plain `AttributedString` derived from the raw string so the
    /// user's typing isn't lost — they just see attributes drop.
    static func makeAttributedString(from ns: NSAttributedString) -> AttributedString {
        do {
            return try AttributedString(ns, including: \.fromInk)
        } catch {
            return AttributedString(ns.string)
        }
    }

    // MARK: - Selection bridging

    /// `AttributedTextSelection → NSRange` over UTF-16 units. Returns
    /// nil if the selection's first range / insertion point can't be
    /// projected into the body (stale indices, empty range set, etc.).
    static func nsRange(
        from selection: AttributedTextSelection,
        in body: AttributedString
    ) -> NSRange? {
        switch selection.indices(in: body) {
        case .insertionPoint(let idx):
            let utf16Offset = utf16Distance(from: body.startIndex, to: idx, in: body)
            return NSRange(location: utf16Offset, length: 0)
        case .ranges(let rangeSet):
            guard let first = rangeSet.ranges.first else { return nil }
            let lower = utf16Distance(from: body.startIndex, to: first.lowerBound, in: body)
            let upper = utf16Distance(from: body.startIndex, to: first.upperBound, in: body)
            return NSRange(location: lower, length: upper - lower)
        }
    }

    /// `NSRange → AttributedTextSelection`. Used by the Coordinator
    /// when UITextView's `textViewDidChangeSelection` fires.
    static func selection(
        from nsRange: NSRange,
        in body: AttributedString
    ) -> AttributedTextSelection {
        let utf16 = body.unicodeScalars  // bridge through utf16 view
        _ = utf16  // suppress
        guard let lowerIdx = utf16Index(at: nsRange.location, in: body) else {
            return AttributedTextSelection()
        }
        if nsRange.length == 0 {
            return AttributedTextSelection(range: lowerIdx..<lowerIdx)
        }
        guard let upperIdx = utf16Index(at: nsRange.location + nsRange.length, in: body) else {
            return AttributedTextSelection(range: lowerIdx..<lowerIdx)
        }
        return AttributedTextSelection(range: lowerIdx..<upperIdx)
    }

    /// UTF-16 offset between two AttributedString indices. UITextView's
    /// `NSRange` is over UTF-16 code units, which matches what the
    /// underlying NSAttributedString uses — convert via the
    /// AttributedString's UTF-16 view rather than character clusters
    /// to keep `NSRange` math consistent with what UITextView reports.
    private static func utf16Distance(
        from start: AttributedString.Index,
        to end: AttributedString.Index,
        in body: AttributedString
    ) -> Int {
        let utf16 = body.unicodeScalars
        _ = utf16
        // AttributedString.UnicodeScalarView indexes into the same
        // backing storage; the distance over UTF-16 code units is the
        // same as the .utf16 view distance against a String built
        // from .characters.
        let stringStart = String(body[body.startIndex..<start].characters)
        let stringEnd = String(body[body.startIndex..<end].characters)
        return stringEnd.utf16.count - stringStart.utf16.count
    }

    /// Map a UTF-16 offset into the AttributedString's index space.
    /// Clamps to end-of-string if the offset overshoots (UITextView
    /// occasionally reports a one-past-end caret during composition).
    private static func utf16Index(at offset: Int, in body: AttributedString) -> AttributedString.Index? {
        let raw = String(body.characters)
        guard offset >= 0 else { return body.startIndex }
        if offset >= raw.utf16.count {
            return body.endIndex
        }
        let utf16Idx = raw.utf16.index(raw.utf16.startIndex, offsetBy: offset)
        guard let stringIdx = utf16Idx.samePosition(in: raw) else {
            // Offset lands inside a surrogate pair — round down to
            // the cluster boundary.
            let safeIdx = utf16Idx.samePosition(in: raw.unicodeScalars)
                ?? raw.unicodeScalars.endIndex
            let stringFallback = safeIdx.samePosition(in: raw) ?? raw.endIndex
            return AttributedString.Index(stringFallback, within: body)
        }
        return AttributedString.Index(stringIdx, within: body)
    }

    // MARK: - Horizontal rule attachment

    /// `NSTextAttachment` that paints a 1pt horizontal rule across
    /// the full line-fragment width. Used to render
    /// `PresentationIntent(.thematicBreak)` paragraphs as actual
    /// dividers rather than empty paragraphs.
    private final class HorizontalRuleAttachment: NSTextAttachment {
        let color: UIColor

        init(color: UIColor) {
            self.color = color
            super.init(data: nil, ofType: nil)
        }

        required init?(coder: NSCoder) {
            self.color = .label
            super.init(coder: coder)
        }

        override func attachmentBounds(
            for textContainer: NSTextContainer?,
            proposedLineFragment lineFrag: CGRect,
            glyphPosition position: CGPoint,
            characterIndex charIndex: Int
        ) -> CGRect {
            CGRect(x: 0, y: -3, width: lineFrag.width, height: 1)
        }

        override func image(
            forBounds imageBounds: CGRect,
            textContainer: NSTextContainer?,
            characterIndex charIndex: Int
        ) -> UIImage? {
            let size = CGSize(width: max(imageBounds.width, 1), height: max(imageBounds.height, 1))
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                color.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextKitEditorView
        weak var textView: UITextView?
        /// Set to `true` while `updateUIView` is programmatically
        /// reseating attributedText / selectedRange. The delegate's
        /// did-change callbacks check this flag and short-circuit so
        /// a binding-driven update doesn't loop back into a binding
        /// write.
        var isApplyingBindingUpdate = false

        init(parent: TextKitEditorView) {
            self.parent = parent
            super.init()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingBindingUpdate else { return }
            let next = TextKitEditorView.makeAttributedString(from: textView.attributedText)
            if next != parent.body {
                parent.body = next
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingBindingUpdate else { return }
            let nsRange = textView.selectedRange
            let next = TextKitEditorView.selection(from: nsRange, in: parent.body)
            // Always push — AttributedTextSelection doesn't have a
            // cheap equality so just rely on the reducer's same-state
            // diff to no-op when nothing changed.
            parent.selection = next
        }
    }
}
#endif
