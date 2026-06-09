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
        // default font/color underneath any explicit per-run font
        // (e.g. TextKit 2's heading auto-sizing). Per-run attributes
        // override the base.
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
        return mutable
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
