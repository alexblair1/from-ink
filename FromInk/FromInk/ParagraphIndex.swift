import Foundation

/// Side-channel index of paragraph identity, owned by the editor's
/// `Coordinator`. Each entry covers one paragraph (one leaf block
/// emitted into the flattened NSAttributedString).
///
/// **Why this exists.** The previous design encoded block identity
/// directly into NSAttributedString attribute keys (`.blockID`,
/// `.groupID`, `.blockChrome`, `.fromInkListItemID`,
/// `.fromInkLanguageHint`). That broke in three ways:
///
///   - UIKit's `typingAttributes` carried identity attributes forward
///     across Enter, causing two adjacent paragraphs to share a
///     blockID and `enumerateAttribute` to consolidate them into one
///     range — only the first paragraph painted its chrome.
///   - UIKit re-derived `typingAttributes` on every selection change
///     and stripped every custom key, requiring a re-assert dance in
///     two delegate methods to keep bullets from disappearing on tap.
///   - `parseBack` had to dedupe identity collisions with fresh UUIDs
///     in the parsed document only — leaving storage and document in
///     disagreement on identity, which the selection bridge had to
///     reconcile mid-typing.
///
/// `ParagraphIndex` is the side channel UIKit can't touch. Identity is
/// explicit at every edit site: structural edits update the index
/// incrementally with fresh blockIDs, reducer-driven mutations update
/// the index alongside the storage edit. The selection bridge, slash
/// trigger, drawBackground discriminator, and document parse-back all
/// read from this single source of truth.
///
/// **Range convention.** `Entry.range` is the paragraph's text range
/// EXCLUDING its trailing `\n` — matching `TextKitEditorView.flatten`'s
/// existing `FlattenMap` contract. An empty paragraph has a
/// zero-length range; its trailing `\n` carries the paragraph's
/// attributes for layout but doesn't extend the range.
struct ParagraphIndex: Equatable, Sendable {

    /// One paragraph's identity + position. `range` is in the editor's
    /// flattened NSAttributedString; the other fields address the
    /// paragraph's place in the document tree.
    struct Entry: Equatable, Sendable {
        /// Paragraph's text range in the storage, excluding the
        /// trailing `\n`. Empty paragraphs have length zero.
        var range: NSRange

        /// Path through the document tree to this paragraph's leaf,
        /// matching `RichTextDocument.block(at:)`'s convention
        /// (container ids included, ListItem ids skipped — see
        /// `RichTextDocument.block(at:)` for the path semantics).
        var blockPath: [UUID]

        /// Semantic kind for rendering + structural decisions. See
        /// `ParagraphKind` for the full set.
        var kind: ParagraphKind

        /// Identity of the enclosing `ListItem` when this paragraph
        /// is a list item's text. Nil for non-list paragraphs.
        /// Carried so list-item identity survives parse-back round
        /// trips (region anchors on list rows will need this).
        var listItemID: UUID?

        /// Optional language hint for `.codeBlock` paragraphs.
        /// Carried for future syntax-highlight work; nil for other
        /// kinds.
        var languageHint: String?

        init(
            range: NSRange,
            blockPath: [UUID],
            kind: ParagraphKind,
            listItemID: UUID? = nil,
            languageHint: String? = nil
        ) {
            self.range = range
            self.blockPath = blockPath
            self.kind = kind
            self.listItemID = listItemID
            self.languageHint = languageHint
        }
    }

    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Build an index whose entry ranges match what
    /// `TextKitEditorView.flatten` would produce for the same document.
    /// Pure — no UIKit access, callable off the main actor, callable
    /// from cross-platform code.
    ///
    /// **Range contract.** Each entry's `range` covers its paragraph's
    /// text only (excluding the trailing `\n`) — matching the existing
    /// `FlattenMap` contract so the two structures address the same
    /// positions identically. An empty paragraph has length zero; its
    /// position is the same character index where the next paragraph's
    /// text begins minus one (the trailing `\n`).
    ///
    /// **Path semantics.** Container ids are included in the path;
    /// `ListItem` ids are skipped per the
    /// `RichTextDocument.block(at:)` convention. This means the index
    /// can address a list-item's text paragraph with
    /// `[bulletList.id, paragraph.id]` and round-trip through
    /// `RichTextDocument.block(at:)` unchanged.
    init(document: RichTextDocument) {
        var entries: [Entry] = []
        var cursor = 0

        func appendEntry(
            text: String,
            blockPath: [UUID],
            kind: ParagraphKind,
            listItemID: UUID? = nil,
            languageHint: String? = nil
        ) {
            // UTF-16 code units — the storage's NSRange convention and
            // the BlockTreeSelection offset convention.
            let length = (text as NSString).length
            entries.append(Entry(
                range: NSRange(location: cursor, length: length),
                blockPath: blockPath,
                kind: kind,
                listItemID: listItemID,
                languageHint: languageHint
            ))
            // +1 for the trailing `\n` that flatten emits after every
            // paragraph — even the last one, per the flatten contract
            // ("don't trim the terminator").
            cursor += length + 1
        }

        func walk(_ block: Block, pathPrefix: [UUID], inBlockquote: Bool) {
            let path = pathPrefix + [block.id]
            switch block.kind {
            case .paragraph(let inline):
                let text = inline.reduce(into: "") { $0.append($1.text) }
                let kind: ParagraphKind = inBlockquote ? .blockquoteParagraph : .paragraph
                appendEntry(text: text, blockPath: path, kind: kind)

            case .heading(let level, let inline):
                let text = inline.reduce(into: "") { $0.append($1.text) }
                appendEntry(text: text, blockPath: path, kind: .heading(level: level))

            case .codeBlock(let text, let languageHint):
                appendEntry(
                    text: text,
                    blockPath: path,
                    kind: .codeBlock,
                    languageHint: languageHint
                )

            case .divider:
                // Divider flattens as the non-breaking space anchor
                // (one UTF-16 unit) so TextKit has a glyph to position
                // the rule against.
                appendEntry(text: "\u{00A0}", blockPath: path, kind: .divider)

            case .bulletList(let items):
                for item in items {
                    for (idx, child) in item.content.enumerated() {
                        if idx == 0, case .paragraph(let inline) = child.kind {
                            let text = inline.reduce(into: "") { $0.append($1.text) }
                            appendEntry(
                                text: text,
                                blockPath: path + [child.id],
                                kind: .bulletListItem,
                                listItemID: item.id
                            )
                        } else {
                            walk(child, pathPrefix: path, inBlockquote: inBlockquote)
                        }
                    }
                }

            case .orderedList(let items):
                for item in items {
                    for (idx, child) in item.content.enumerated() {
                        if idx == 0, case .paragraph(let inline) = child.kind {
                            let text = inline.reduce(into: "") { $0.append($1.text) }
                            appendEntry(
                                text: text,
                                blockPath: path + [child.id],
                                kind: .orderedListItem,
                                listItemID: item.id
                            )
                        } else {
                            walk(child, pathPrefix: path, inBlockquote: inBlockquote)
                        }
                    }
                }

            case .blockquote(let children):
                for child in children {
                    walk(child, pathPrefix: path, inBlockquote: true)
                }
            }
        }

        for block in document.blocks {
            walk(block, pathPrefix: [], inBlockquote: false)
        }
        self.entries = entries
    }

    /// Leaf-block id at the tail of each entry's `blockPath`. Used by
    /// the selection bridge to map a probed paragraph back to a
    /// `BlockTreeSelection`.
    func entry(forLeafID leafID: UUID) -> Entry? {
        entries.first { $0.blockPath.last == leafID }
    }

    /// Adjust entry ranges in place for a *non-structural* text edit —
    /// one that changes characters within a single paragraph without
    /// adding, removing, or merging any paragraph (no `\n` inserted or
    /// deleted).
    ///
    /// `editedRange` is the replaced range in PRE-edit storage
    /// coordinates; `newLength` is the UTF-16 length of the text that
    /// replaced it. The host paragraph (the one containing
    /// `editedRange.location`) grows or shrinks by the delta, and every
    /// later paragraph shifts by the same delta. Identity — `blockPath`,
    /// `kind`, `listItemID`, `languageHint` — is untouched, because a
    /// within-paragraph edit can't change which block a paragraph is.
    ///
    /// **Why only non-structural.** The editor routes every structural
    /// edit (Enter, paste containing `\n`, cross-paragraph delete)
    /// through an immediate full rebuild (`syncDocumentFromStorage` →
    /// `ParagraphIndex(document:)`), so the incremental path never has
    /// to mint fresh blockIDs or split/merge entries. It exists purely
    /// to keep ranges accurate between a plain keystroke and the
    /// debounced sync that follows it — the window in which a live
    /// reader (the layout manager's chrome paint, the selection bridge)
    /// would otherwise see stale offsets.
    ///
    /// No-ops when the delta is zero or `editedRange.location` falls
    /// past the last paragraph (the phantom-tail position after the
    /// document's final `\n`, which the caret never rests at).
    mutating func applyNonStructuralEdit(editedRange: NSRange, newLength: Int) {
        let delta = newLength - editedRange.length
        guard delta != 0 else { return }
        // Host = the paragraph containing the edit's start. Inclusive
        // on both ends, earlier paragraph wins at a shared boundary —
        // the same rule `entry(containing:)` uses, so the live reader
        // and this maintainer agree on which paragraph an edit belongs
        // to.
        guard let host = entries.firstIndex(where: { entry in
            editedRange.location >= entry.range.location
                && editedRange.location <= entry.range.location + entry.range.length
        }) else { return }
        entries[host].range.length += delta
        for i in entries.indices where i > host {
            entries[i].range.location += delta
        }
    }

    /// Update the index for an Enter that splits the paragraph at
    /// `location` into two. The FIRST half keeps the original
    /// paragraph's identity (the original is left in place); the SECOND
    /// half becomes a NEW paragraph with a fresh leaf id, its kind and
    /// container inherited per the editor's split policy — matching what
    /// `paragraphIdentityFixups` + `parseBack` produce today, so the
    /// index stays authoritative across Enter even when UIKit corrupts
    /// the storage's identity attributes:
    ///
    ///   - paragraph → second half is a top-level `.paragraph`
    ///   - heading → second half DEMOTES to a top-level `.paragraph`
    ///     (Enter after a heading drops to body)
    ///   - bullet / ordered list item → second half is a NEW item of
    ///     the same kind in the SAME list container, with a fresh
    ///     `listItemID`
    ///   - blockquote paragraph → second half is another blockquote
    ///     paragraph in the same container
    ///
    /// `replacingLength` covers the **selection + Enter** case: if a
    /// non-zero selection at `[location, location + replacingLength)`
    /// is being replaced by the `\n`, the host paragraph loses those
    /// chars before the split. Default `0` is the pure Enter case
    /// (caret at `location`, no chars deleted).
    ///
    /// A `\n` lives at `location` after the edit; the first half's
    /// terminator becomes that newline. Every paragraph after the new
    /// second half shifts by `(1 - replacingLength)` — `+1` for the
    /// inserted `\n`, minus the chars the selection deleted. `makeID`
    /// mints fresh ids (injectable for deterministic tests). No-op when
    /// `location` falls outside every entry (the phantom tail), or when
    /// the host paragraph isn't long enough to absorb the deletion
    /// (defensive — the caller is expected to have verified the range
    /// stays within one paragraph).
    ///
    /// Code blocks are treated as a top-level paragraph split for now —
    /// Enter inside a code block (an internal newline, not a block
    /// split) is a separate case the editor doesn't yet route here.
    mutating func applyStructuralSplit(
        at location: Int,
        replacingLength: Int = 0,
        makeID: () -> UUID = { UUID() }
    ) {
        guard let i = entries.firstIndex(where: { entry in
            location >= entry.range.location
                && location <= entry.range.location + entry.range.length
        }) else { return }
        let original = entries[i]
        let firstLength = location - original.range.location
        // The host loses `replacingLength` chars to the selection
        // delete; only the remainder lands in the second half.
        let secondLength = original.range.length - firstLength - replacingLength
        guard secondLength >= 0 else { return }

        // First half keeps identity; shrink to the pre-split portion.
        // Its terminator is now the inserted `\n` at `location`.
        entries[i].range = NSRange(location: original.range.location, length: firstLength)

        // Second half: fresh identity per the split policy above.
        let container = Array(original.blockPath.dropLast())
        let second: Entry
        switch original.kind {
        case .bulletListItem, .orderedListItem:
            second = Entry(
                range: NSRange(location: location + 1, length: secondLength),
                blockPath: container + [makeID()],
                kind: original.kind,
                listItemID: makeID()
            )
        case .blockquoteParagraph:
            second = Entry(
                range: NSRange(location: location + 1, length: secondLength),
                blockPath: container + [makeID()],
                kind: .blockquoteParagraph
            )
        case .paragraph, .heading, .codeBlock, .divider:
            // Top-level body paragraph (heading demotes to body).
            second = Entry(
                range: NSRange(location: location + 1, length: secondLength),
                blockPath: [makeID()],
                kind: .paragraph
            )
        }
        entries.insert(second, at: i + 1)

        // Everything after the new second half shifts by the net delta:
        // `+1` for the inserted `\n`, minus the deleted selection chars.
        let shift = 1 - replacingLength
        for j in entries.indices where j > i + 1 {
            entries[j].range.location += shift
        }
    }

    /// Update the index for a backspace/delete that removes the `\n`
    /// between a paragraph and its predecessor, merging the two into
    /// one. `location` is the start of the paragraph being merged UP
    /// (the caret's paragraph before a backspace-at-start).
    ///
    /// The predecessor ABSORBS the merged paragraph's text and keeps its
    /// own identity + kind — matching `parseBack`, which reads the merged
    /// paragraph's attributes from its (now the predecessor's) first
    /// character. So merging a body paragraph up into a list item leaves
    /// a list item; merging two list items leaves one item in the same
    /// container.
    ///
    /// No-op when no paragraph starts exactly at `location`, or when it
    /// is the first paragraph (nothing to merge into).
    mutating func applyStructuralMerge(atParagraphStart location: Int) {
        guard let b = entries.firstIndex(where: { $0.range.location == location }), b > 0 else { return }
        let a = b - 1
        // The `\n` was the predecessor's terminator (never counted in
        // its range), so the predecessor simply grows by the merged
        // paragraph's text length.
        entries[a].range.length += entries[b].range.length
        entries.remove(at: b)
        // Everything from the removed paragraph onward shifts back by
        // the deleted `\n`.
        for j in entries.indices where j >= b {
            entries[j].range.location -= 1
        }
    }

    /// Apply a single text edit — generalizes the
    /// non-structural / structural distinction into one operation that
    /// handles ANY `(range, replacement)` pair `shouldChangeTextIn`
    /// captures: pure within-paragraph edits, single-`\n` insert (Enter,
    /// selection + Enter), single-`\n` delete (backspace-merge),
    /// multi-`\n` insert (multi-line paste), multi-`\n` delete
    /// (cross-paragraph delete), and arbitrary replacements that
    /// combine inserts and deletes.
    ///
    /// **Identity rules.** The FIRST result paragraph inherits the
    /// host's identity (the paragraph the edit starts in). Every
    /// additional result paragraph gets fresh identity per the same
    /// split policy `applyStructuralSplit` uses:
    ///   - inside a bullet list → new ListItem in the same container
    ///   - inside an ordered list → new ListItem in the same container
    ///   - inside a blockquote → new blockquote child
    ///   - otherwise → top-level body paragraph (heading demotes)
    ///
    /// When `replacement` contains no `\n` AND the edit doesn't cross a
    /// paragraph boundary in the pre-edit index, this collapses the
    /// affected entries (just the host) into one entry inheriting the
    /// host's identity — equivalent to an inline replacement.
    ///
    /// When `replacement` contains no `\n` BUT the edit CROSSES one or
    /// more boundaries (cross-paragraph delete with non-empty
    /// replacement), the affected entries fuse into one entry
    /// inheriting the host's (first) identity.
    ///
    /// **Precondition.** `editedRange.location` must address a
    /// paragraph in the index. No-op when it falls past the last
    /// paragraph (the phantom-tail position) or when `entries` is empty.
    mutating func applyEdit(
        replacing editedRange: NSRange,
        with replacement: String,
        makeID: () -> UUID = { UUID() }
    ) {
        guard !entries.isEmpty else { return }
        let editStart = editedRange.location
        let editEnd = editedRange.location + editedRange.length
        // `editEnd` can land on the phantom-tail position (past the
        // last entry's text end) when the user select-alls or extends
        // a selection past the document's final `\n`. Clamp it to the
        // last entry's text end so the lookup below still resolves;
        // the trailing `\n` itself isn't in any entry's range, so the
        // shift math below uses the ORIGINAL `editedRange.length` to
        // account for the chars actually removed from storage.
        let lastEntryEnd = entries[entries.count - 1].range.location
            + entries[entries.count - 1].range.length
        let clampedEditEnd = min(editEnd, lastEntryEnd)
        guard let firstIdx = entries.firstIndex(where: { e in
            editStart >= e.range.location
                && editStart <= e.range.location + e.range.length
        }) else { return }
        let lastIdx: Int
        if editedRange.length == 0 {
            lastIdx = firstIdx
        } else if let idx = entries.firstIndex(where: { e in
            clampedEditEnd >= e.range.location
                && clampedEditEnd <= e.range.location + e.range.length
        }) {
            lastIdx = idx
        } else {
            return
        }
        let firstEntry = entries[firstIdx]
        let lastEntry = entries[lastIdx]
        let prefixLength = editStart - firstEntry.range.location
        let suffixStart = clampedEditEnd - lastEntry.range.location
        let suffixLength = lastEntry.range.length - suffixStart
        guard prefixLength >= 0, suffixLength >= 0 else { return }

        let nsReplacement = replacement as NSString
        let replacementLength = nsReplacement.length
        let segments = replacement.components(separatedBy: "\n")

        // Container path for fresh entries — split policy keys off the
        // host's container, matching `applyStructuralSplit`.
        let container = Array(firstEntry.blockPath.dropLast())

        func freshEntry(at location: Int, length: Int) -> Entry {
            switch firstEntry.kind {
            case .bulletListItem, .orderedListItem:
                return Entry(
                    range: NSRange(location: location, length: length),
                    blockPath: container + [makeID()],
                    kind: firstEntry.kind,
                    listItemID: makeID()
                )
            case .blockquoteParagraph:
                return Entry(
                    range: NSRange(location: location, length: length),
                    blockPath: container + [makeID()],
                    kind: .blockquoteParagraph
                )
            case .paragraph, .heading, .codeBlock, .divider:
                return Entry(
                    range: NSRange(location: location, length: length),
                    blockPath: [makeID()],
                    kind: .paragraph
                )
            }
        }

        var newEntries: [Entry] = []
        var cursor = firstEntry.range.location

        if segments.count == 1 {
            // No paragraph boundary introduced by the replacement.
            // First through last entries collapse into ONE entry
            // inheriting the host's identity — prefix + replacement +
            // suffix.
            let segLength = (segments[0] as NSString).length
            let totalLength = prefixLength + segLength + suffixLength
            newEntries.append(Entry(
                range: NSRange(location: cursor, length: totalLength),
                blockPath: firstEntry.blockPath,
                kind: firstEntry.kind,
                listItemID: firstEntry.listItemID,
                languageHint: firstEntry.languageHint
            ))
            cursor += totalLength + 1
        } else {
            // First new paragraph: prefix + segments[0], inherits the
            // host's identity.
            let firstSegLength = (segments[0] as NSString).length
            let firstNewLength = prefixLength + firstSegLength
            newEntries.append(Entry(
                range: NSRange(location: cursor, length: firstNewLength),
                blockPath: firstEntry.blockPath,
                kind: firstEntry.kind,
                listItemID: firstEntry.listItemID,
                languageHint: firstEntry.languageHint
            ))
            cursor += firstNewLength + 1
            // Middle segments (if any): fresh paragraphs per the split
            // policy.
            if segments.count > 2 {
                for i in 1..<(segments.count - 1) {
                    let segLength = (segments[i] as NSString).length
                    newEntries.append(freshEntry(at: cursor, length: segLength))
                    cursor += segLength + 1
                }
            }
            // Last new paragraph: segments[last] + suffix, fresh identity.
            let lastSegLength = (segments[segments.count - 1] as NSString).length
            let lastNewLength = lastSegLength + suffixLength
            newEntries.append(freshEntry(at: cursor, length: lastNewLength))
            cursor += lastNewLength + 1
        }

        entries.replaceSubrange(firstIdx...lastIdx, with: newEntries)

        // Shift later (untouched) entries by the edit's net delta.
        let netDelta = replacementLength - editedRange.length
        let firstUntouchedIdx = firstIdx + newEntries.count
        for i in entries.indices where i >= firstUntouchedIdx {
            entries[i].range.location += netDelta
        }
    }

    /// Entry whose paragraph range contains `location`.
    ///
    /// **Boundary semantics.** Inclusive on both ends. At the position
    /// equal to the END of one paragraph's text (e.g. position 5 for
    /// the paragraph "Hello"), the EARLIER paragraph wins — the next
    /// paragraph's range starts at the position AFTER the `\n`
    /// terminator (position 6), so the end-of-paragraph caret routes
    /// to its host paragraph. This matches UIKit's `typingAttributes`
    /// "extend the current paragraph" convention.
    ///
    /// Returns nil when `location` is past the last paragraph (the
    /// "phantom tail" position after the document's final `\n`) — the
    /// caller is responsible for snapping or treating as unset.
    func entry(containing location: Int) -> Entry? {
        for entry in entries {
            if location >= entry.range.location,
               location <= entry.range.location + entry.range.length {
                return entry
            }
        }
        return nil
    }
}
