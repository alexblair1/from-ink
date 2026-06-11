import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "TextEditingFeature")

/// Owns the state and effects for editing a single text block.
///
/// **Scope.** This feature edits ONE block at a time — the active text
/// block on the current page.
///
/// **Content model.** State holds a `RichTextDocument` (the block-tree
/// shape from `text_experience_edd.md` §5.3) — paragraphs, headings,
/// lists, blockquote, codeBlock, divider with inline runs and Marks.
/// `AttributedString` is no longer in the state surface; the block
/// tree is what gets persisted, edited, and addressed by NoteRegion
/// text anchors.
///
/// **Persistence.** Every document change debounces a `NotebookClient.
/// updateBlockBody` write. Debounce window is 600ms.
///
/// **Encoding.** Document archival routes through
/// `PageBlockSnapshot.encodeBody(_:)` so the JSON encoder + sorted-keys
/// canonicalisation lives in one place. The byte-stable encoding is
/// load-bearing for `PageBlock.contentHash`.
///
/// **Selection tracking.** `BlockTreeSelection` (a path + UTF-16 offset
/// range) addresses positions inside the document tree. Block-format
/// actions resolve the host leaf via `path`; inline-format actions
/// apply marks across the offsets inside the host leaf's inline runs.
///
/// **Slash command palette.** Scoped under `.slashPalette`. The editor
/// (post-commit-4) detects a `/` at word-boundary inside a leaf and
/// sends `.slashTyped(...)`. The reducer opens the palette, tracking
/// the trigger leaf path + offset; subsequent `documentEdited`s
/// recompute the filter from the leaf's current text.
///
/// **Equality cost.** `RichTextDocument.Equatable` is O(n) over blocks
/// + inline runs. Typical block sizes (<10KB) compare in well under
/// 1ms. EDD §5.4 documents the 50KB hash-based-equality threshold.
struct TextEditingFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var activeBlock: PageBlockSnapshot? = nil

        /// The block-tree being edited. Defaults to `.empty` when no
        /// block is active or the active block is non-text.
        var document: RichTextDocument = .empty

        /// Caret / range position inside the document. See
        /// `BlockTreeSelection` for the path-based addressing scheme.
        ///
        /// **Default value semantics.** `BlockTreeSelection()` (empty
        /// path, offset zero) is treated as "unset" — block-format
        /// actions resolve unset to the document's last leaf,
        /// mirroring the prior `AttributedTextSelection()` default-
        /// end-of-document contract.
        var selection: BlockTreeSelection = BlockTreeSelection()

        var isDirty: Bool = false

        var loadFailure: LoadFailure? = nil

        var lastPersistFailureReason: String? = nil

        /// Slash command palette state, scoped under this feature.
        var slashPalette: SlashCommandPaletteFeature.State = .init()

        enum LoadFailure: Equatable, Sendable {
            case bodyDecodeFailed
            case orphan
        }
    }

    @CasePathable
    enum Action: Equatable {
        case activeBlockChanged(PageBlockSnapshot?)

        /// The editor reports a fresh document after a keystroke,
        /// paste, or programmatic mutation. The reducer mirrors,
        /// marks dirty, refreshes the slash filter if the palette is
        /// open, and schedules a debounced persist.
        case documentEdited(RichTextDocument)

        /// User's caret / range selection changed. Block / inline
        /// format actions read this to target the right span.
        case selectionChanged(BlockTreeSelection)

        /// The editor detected the user typing `/` at a word boundary
        /// inside the leaf at `blockPath`, at UTF-16 offset within
        /// that leaf's joined inline text. Opens the palette and
        /// records the trigger location so subsequent edits can
        /// refresh the filter.
        case slashTyped(blockPath: [UUID], offsetUTF16: Int)

        case persistRequested
        case persistCompleted
        case persistFailed(reason: String)

        case flush

        /// Apply a block-level format. The selection's leaf (or the
        /// last leaf if unset) is targeted.
        case applyBlockFormat(BlockFormat)

        /// Toggle an inline format across the selection's UTF-16
        /// range. Insertion-point-only selections no-op.
        case toggleInlineFormat(InlineFormat)

        /// Exit the current list: convert the (empty) list-item
        /// paragraph at `selection.path` into a body paragraph
        /// and split the surrounding list if needed. Fired by the
        /// editor's `shouldChangeTextIn` when the user presses
        /// Enter on an empty list item — see `EditorCommand.exitList`.
        case exitList

        /// Split the current leaf at the cursor, creating a new
        /// leaf below with the post-cursor text. List items split
        /// into adjacent list items; headings split into the
        /// heading + a body paragraph (Enter doesn't propagate the
        /// heading). Fired by the editor's `shouldChangeTextIn`
        /// when the user presses Enter — see
        /// `EditorCommand.insertParagraph`.
        case insertParagraph

        case slashPalette(SlashCommandPaletteFeature.Action)
    }

    enum BlockFormat: Equatable, Sendable {
        case heading(level: Int)   // 1, 2, 3
        case body
        case blockQuote
        case codeBlock
        case bulletedList
        case numberedList
        case divider
    }

    enum InlineFormat: Equatable, Sendable {
        case bold
        case italic
        case underline
        case strikethrough
        case code
    }

    @Dependency(\.notebookClient) var notebookClient
    @Dependency(\.continuousClock) var clock

    private static let persistCancelID = "TextEditingFeature.persist"
    private static let debounceMilliseconds: Int = 600

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .activeBlockChanged(let snapshot):
                // Same-block echo (SwiftData notification fans back to
                // this reducer with the same snapshot we just
                // persisted). Refresh only failure / metadata; leave
                // live editor state (document, selection, palette,
                // dirty) intact.
                if let snapshot,
                   let current = state.activeBlock,
                   snapshot.id == current.id {
                    state.activeBlock = snapshot
                    state.loadFailure = Self.loadFailure(for: snapshot)
                    return .none
                }

                // Fresh block — reset everything.
                state.activeBlock = snapshot
                if let snapshot {
                    state.loadFailure = Self.loadFailure(for: snapshot)
                    state.document = snapshot.document ?? .empty
                } else {
                    state.loadFailure = nil
                    state.document = .empty
                }
                state.selection = BlockTreeSelection()
                state.isDirty = false
                state.lastPersistFailureReason = nil
                state.slashPalette = .init()
                return .cancel(id: Self.persistCancelID)

            case .documentEdited(let new):
                guard state.loadFailure == nil else { return .none }
                state.document = new
                state.isDirty = true

                if state.slashPalette.isOpen {
                    // Refresh the filter from the trigger leaf's
                    // current text — or dismiss if the trigger is
                    // gone (user backspaced past the `/`, or moved
                    // focus away).
                    return .merge(
                        schedulePersist(),
                        refreshSlashFilterEffect(state: state)
                    )
                }
                return schedulePersist()

            case .selectionChanged(let new):
                state.selection = new
                return .none

            case .slashTyped(let path, let offset):
                guard state.loadFailure == nil else { return .none }
                return .send(.slashPalette(.openRequested(
                    triggerOffset: offset,
                    triggerBlockPath: path
                )))

            case .persistRequested:
                return persistEffect(state: state)

            case .persistCompleted:
                state.isDirty = false
                state.lastPersistFailureReason = nil
                return .none

            case .persistFailed(let reason):
                log.error("Body persist failed: \(reason, privacy: .public)")
                state.lastPersistFailureReason = reason
                return .none

            case .flush:
                guard state.isDirty, state.loadFailure == nil else {
                    return .cancel(id: Self.persistCancelID)
                }
                return .merge(
                    .cancel(id: Self.persistCancelID),
                    persistEffect(state: state)
                )

            case .applyBlockFormat(let format):
                guard state.loadFailure == nil else { return .none }
                // Pass both as inout via local vars — Swift's
                // exclusivity rules forbid two `&state.foo` inouts in
                // one call (memory rule on MainActor isolation).
                var doc = state.document
                var sel = state.selection
                Self.applyBlockFormat(
                    format,
                    document: &doc,
                    selection: &sel
                )
                state.document = doc
                state.selection = sel
                state.isDirty = true
                return schedulePersist()

            case .toggleInlineFormat(let format):
                guard state.loadFailure == nil else { return .none }
                Self.toggleInlineFormat(
                    format,
                    document: &state.document,
                    selection: state.selection
                )
                state.isDirty = true
                return schedulePersist()

            case .exitList:
                guard state.loadFailure == nil else { return .none }
                // Capture-mutate-write-back: Swift exclusivity rules
                // forbid passing two `&state.*` inouts in one call
                // (memory rule under MainActor isolation).
                var doc = state.document
                var sel = state.selection
                let didExit = Self.exitList(document: &doc, selection: &sel)
                guard didExit else { return .none }
                state.document = doc
                state.selection = sel
                state.isDirty = true
                return schedulePersist()

            case .insertParagraph:
                guard state.loadFailure == nil else { return .none }
                var doc = state.document
                var sel = state.selection
                let didSplit = Self.insertParagraphAtCursor(document: &doc, selection: &sel)
                guard didSplit else { return .none }
                state.document = doc
                state.selection = sel
                state.isDirty = true
                return schedulePersist()

            case .slashPalette(.commandSelected(let command)):
                if !state.slashPalette.triggerBlockPath.isEmpty,
                   let triggerOffset = state.slashPalette.triggerOffset {
                    Self.stripTriggerSlice(
                        document: &state.document,
                        leafPath: state.slashPalette.triggerBlockPath,
                        triggerOffsetUTF16: triggerOffset
                    )
                    // Reset selection to the position where the trigger
                    // USED to be — the strip removed [trigger..end] of
                    // the leaf, so the caret lands at the trigger
                    // offset (which is now end-of-leaf). Without this,
                    // any subsequent inline-format action would target
                    // stale UTF-16 offsets past the new end of text.
                    state.selection = .insertion(
                        at: state.slashPalette.triggerBlockPath,
                        offset: triggerOffset
                    )
                }
                let formatAction = Self.blockFormatAction(for: command)
                if let formatAction {
                    state.isDirty = true
                    return .merge(
                        .send(formatAction),
                        schedulePersist()
                    )
                }
                return schedulePersist()

            case .slashPalette:
                return .none
            }
        }

        Scope(state: \.slashPalette, action: \.slashPalette) {
            SlashCommandPaletteFeature()
        }
    }

    // MARK: - LoadFailure resolution

    private static func loadFailure(for snapshot: PageBlockSnapshot) -> State.LoadFailure? {
        if snapshot.pageID == nil { return .orphan }
        if snapshot.bodyDecodeFailed { return .bodyDecodeFailed }
        return nil
    }

    // MARK: - Slash filter refresh

    /// After every `documentEdited` while the palette is open, walk to
    /// the trigger leaf, find the `/` at the trigger offset, and
    /// re-derive the filter from the slice after it. Dismiss if the
    /// trigger location is no longer valid.
    ///
    /// **Capture semantics.** The values pulled off `state` here
    /// (`path`, `offset`, `document`) are captured by value into the
    /// `Effect.run` closure that this method returns. The caller
    /// ALREADY mutated `state.document = new` before invoking this —
    /// so `document` below is the post-edit value, which is what we
    /// want. Don't move this method's body inline above the
    /// assignment or the capture would see the pre-edit document.
    private func refreshSlashFilterEffect(state: State) -> Effect<Action> {
        let path = state.slashPalette.triggerBlockPath
        let offset = state.slashPalette.triggerOffset
        let document = state.document

        guard !path.isEmpty,
              let triggerOffset = offset,
              let leaf = document.block(at: path),
              let text = leaf.joinedInlineText else {
            return .send(.slashPalette(.dismissed))
        }

        let utf16 = text.utf16
        guard triggerOffset < utf16.count else {
            return .send(.slashPalette(.dismissed))
        }

        // Confirm the trigger character is still a `/` at that
        // position. If it isn't, the user deleted past it.
        let triggerIdx = utf16.index(utf16.startIndex, offsetBy: triggerOffset)
        let triggerUnit = utf16[triggerIdx]
        let slash: UInt16 = 0x2F  // ASCII "/"
        guard triggerUnit == slash else {
            return .send(.slashPalette(.dismissed))
        }

        // Filter is the slice after the trigger.
        let afterTriggerIdx = utf16.index(after: triggerIdx)
        let filter = String(decoding: Array(utf16[afterTriggerIdx...]), as: UTF16.self)
        if filter.contains(where: { $0.isNewline }) {
            return .send(.slashPalette(.dismissed))
        }
        return .send(.slashPalette(.filterChanged(filter)))
    }

    // MARK: - Persist

    private func schedulePersist() -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: .milliseconds(Self.debounceMilliseconds))
            await send(.persistRequested)
        }
        .cancellable(id: Self.persistCancelID, cancelInFlight: true)
    }

    private func persistEffect(state: State) -> Effect<Action> {
        guard let blockID = state.activeBlock?.id else { return .none }
        let document = state.document
        return .run { send in
            do {
                let data = try PageBlockSnapshot.encodeBody(document)
                let plain = document.plainText
                try await notebookClient.updateBlockBody(blockID, data, plain)
                await send(.persistCompleted)
            } catch {
                await send(.persistFailed(reason: error.localizedDescription))
            }
        }
    }

    // MARK: - Slash command → action

    private static func blockFormatAction(for command: SlashCommand) -> Action? {
        switch command {
        case .heading1:     return .applyBlockFormat(.heading(level: 1))
        case .heading2:     return .applyBlockFormat(.heading(level: 2))
        case .heading3:     return .applyBlockFormat(.heading(level: 3))
        case .body:         return .applyBlockFormat(.body)
        case .blockQuote:   return .applyBlockFormat(.blockQuote)
        case .code:         return .applyBlockFormat(.codeBlock)
        case .bulletedList: return .applyBlockFormat(.bulletedList)
        case .numberedList: return .applyBlockFormat(.numberedList)
        case .divider:      return .applyBlockFormat(.divider)
        // The remaining commands (checklist, region, link, event,
        // pdfAttach, voiceMemo, image, dispatch) defer to follow-up
        // commits — each needs a dependency (custom checklist block,
        // NoteRegion text anchor, link sheet, EventKit picker, file
        // picker, SpeechService, PhotosPicker, DispatchFeature
        // integration) that isn't part of the content-shape pivot.
        default: return nil
        }
    }
}

// MARK: - Block tree edits

extension TextEditingFeature {

    /// Strip the slash trigger + any filter text the user typed from
    /// the leaf at `leafPath`. The trigger offset is in UTF-16 units
    /// of the leaf's joined inline text; everything from the trigger
    /// to the end of the leaf is removed.
    ///
    /// **Mark preservation (fix C3).** Walks the existing inline runs,
    /// keeping runs that fall entirely before the trigger offset, and
    /// truncating the run that straddles the trigger boundary while
    /// preserving its marks. Runs after the trigger are dropped. If
    /// the user bolded text BEFORE typing the slash, the bold survives
    /// the strip.
    fileprivate static func stripTriggerSlice(
        document: inout RichTextDocument,
        leafPath: [UUID],
        triggerOffsetUTF16: Int
    ) {
        document.mapLeaf(at: leafPath) { leaf in
            switch leaf.kind {
            case .paragraph(let inline):
                let truncated = truncateInlineRuns(inline, atUTF16: triggerOffsetUTF16)
                leaf.kind = .paragraph(inline: truncated)
            case .heading(let level, let inline):
                let truncated = truncateInlineRuns(inline, atUTF16: triggerOffsetUTF16)
                leaf.kind = .heading(level: level, inline: truncated)
            case .codeBlock(let text, let hint):
                // codeBlock has no inline runs — straight UTF-16 prefix.
                let utf16 = text.utf16
                guard triggerOffsetUTF16 <= utf16.count else { return }
                let truncated = String(
                    decoding: Array(utf16.prefix(triggerOffsetUTF16)),
                    as: UTF16.self
                )
                leaf.kind = .codeBlock(text: truncated, languageHint: hint)
            case .divider, .bulletList, .orderedList, .blockquote:
                return
            }
        }
    }

    /// Truncate a list of inline runs at the given UTF-16 offset.
    /// Runs that fall entirely before the offset survive verbatim with
    /// all marks intact. The run straddling the offset gets its text
    /// truncated but its marks preserved. Runs after the offset are
    /// dropped.
    fileprivate static func truncateInlineRuns(
        _ runs: [Inline],
        atUTF16 cutoff: Int
    ) -> [Inline] {
        splitInlineRuns(runs, atUTF16: cutoff).first
    }

    /// Split a list of inline runs at the given UTF-16 offset into the
    /// runs before the offset and the runs at-or-after it. The run
    /// straddling the boundary is carved into two runs that each keep
    /// the original's marks — splitting bold text mid-run yields two
    /// bold runs. Offsets clamp: `cutoff <= 0` puts everything in
    /// `second`; `cutoff >= total length` puts everything in `first`.
    fileprivate static func splitInlineRuns(
        _ runs: [Inline],
        atUTF16 cutoff: Int
    ) -> (first: [Inline], second: [Inline]) {
        guard cutoff > 0 else { return ([], runs) }
        var first: [Inline] = []
        var second: [Inline] = []
        var cursor = 0
        for run in runs {
            let runUTF16Count = run.text.utf16.count
            if cursor >= cutoff {
                second.append(run)
            } else if cursor + runUTF16Count <= cutoff {
                first.append(run)
            } else {
                // Run straddles the cutoff — carve, keep marks on
                // both halves.
                let localCutoff = cutoff - cursor
                let utf16 = run.text.utf16
                let splitIdx = utf16.index(utf16.startIndex, offsetBy: localCutoff)
                let firstText = String(decoding: Array(utf16[utf16.startIndex..<splitIdx]), as: UTF16.self)
                let secondText = String(decoding: Array(utf16[splitIdx..<utf16.endIndex]), as: UTF16.self)
                if !firstText.isEmpty {
                    first.append(Inline(text: firstText, marks: run.marks))
                }
                if !secondText.isEmpty {
                    second.append(Inline(text: secondText, marks: run.marks))
                }
            }
            cursor += runUTF16Count
        }
        return (first, second)
    }

    /// Apply a block-level format to the leaf at `selection.path`. If
    /// the selection is unset, the document's last leaf is targeted.
    ///
    /// **Leaf identity preservation (fix C2).** Wrapping a leaf in a
    /// container (blockquote / bulletList / orderedList) KEEPS the
    /// leaf's `id` on the inner paragraph that carries the user's
    /// content; the new outer container gets a fresh UUID. This means:
    ///
    ///   - The block tree's leaf identity follows the content. A
    ///     NoteRegion text anchor that pointed at the leaf BEFORE the
    ///     wrap still has a structurally valid target after the wrap —
    ///     same id, content unchanged, just nested deeper.
    ///   - `BlockTreeSelection.path` MUST be updated to prefix with
    ///     the new outer container's id, otherwise the editor's caret
    ///     would still be addressed by the old top-level path and no
    ///     longer resolve.
    ///   - NoteRegion anchor sweep (separate concern; lands with the
    ///     text-range NoteRegion commit) is responsible for rewriting
    ///     stored `anchorBlockPath` arrays the same way.
    ///
    /// **Divider order (fix C1).** Divider inserts BELOW the target
    /// leaf as a horizontal rule. The caller expects
    /// `[..., target, divider, fresh paragraph, ...]` — caret on the
    /// fresh paragraph so typing continues below the rule. Insert
    /// order: paragraph first, then divider — both anchored after the
    /// target leaf. Each insert lands at `target index + 1`, so the
    /// second insert displaces the first to `target index + 2`.
    fileprivate static func applyBlockFormat(
        _ format: BlockFormat,
        document: inout RichTextDocument,
        selection: inout BlockTreeSelection
    ) {
        // Resolve the target leaf — either via the selection's path
        // or the document's last leaf.
        let targetID: UUID
        if let last = selection.path.last {
            targetID = last
        } else if let lastLeaf = document.lastLeafBlock {
            targetID = lastLeaf.id
        } else {
            // Empty document — seed a paragraph and target it. Inline
            // (no recursion) so the selection update below sees the
            // expected pre-state.
            let paragraph = Block(kind: .paragraph(inline: []))
            document.blocks.append(paragraph)
            selection = .insertion(at: [paragraph.id], offset: 0)
            applyBlockFormat(format, document: &document, selection: &selection)
            return
        }

        // Divider — insert paragraph then divider, both after target.
        // Order matters: see doc comment above.
        if case .divider = format {
            let paragraph = Block(kind: .paragraph(inline: []))
            document.insertBlock(paragraph, afterLeafID: targetID)
            document.insertBlock(Block(kind: .divider), afterLeafID: targetID)
            // Caret lands on the fresh paragraph below the rule.
            // Update selection.path: drop the last path component
            // (the divider's target leaf) and replace with the new
            // paragraph's id at the same nesting level.
            if !selection.path.isEmpty {
                var newPath = selection.path
                newPath[newPath.count - 1] = paragraph.id
                selection = .insertion(at: newPath, offset: 0)
            } else {
                selection = .insertion(at: [paragraph.id], offset: 0)
            }
            return
        }

        // Track which leaf id should be the addressable leaf AFTER the
        // operation, plus the path prefix to prepend on a wrap.
        var newOuterIDForWrap: UUID? = nil

        document.replaceLeaf(id: targetID) { existing in
            let existingInline = existing.kind.inlineRuns
            let existingText = existingInline?.reduce(into: "") { $0.append($1.text) } ?? ""

            switch format {
            case .heading(let level):
                return Block(id: existing.id, kind: .heading(level: level, inline: existingInline ?? []))

            case .body:
                return Block(id: existing.id, kind: .paragraph(inline: existingInline ?? []))

            case .blockQuote:
                // Inner KEEPS existing.id so leaf identity follows
                // the content. Outer wrapper gets a fresh UUID.
                let wrapperID = UUID()
                newOuterIDForWrap = wrapperID
                return Block(id: wrapperID, kind: .blockquote(children: [existing]))

            case .codeBlock:
                // codeBlock is plain text by construction — inline
                // marks discard intentionally. If we ever round-trip
                // paragraph → code → paragraph the marks are gone for
                // good; that's the documented semantic.
                return Block(id: existing.id, kind: .codeBlock(text: existingText, languageHint: nil))

            case .bulletedList:
                let wrapperID = UUID()
                newOuterIDForWrap = wrapperID
                let paragraph = Block(id: existing.id, kind: .paragraph(inline: existingInline ?? []))
                return Block(id: wrapperID, kind: .bulletList(items: [ListItem(content: [paragraph])]))

            case .numberedList:
                let wrapperID = UUID()
                newOuterIDForWrap = wrapperID
                let paragraph = Block(id: existing.id, kind: .paragraph(inline: existingInline ?? []))
                return Block(id: wrapperID, kind: .orderedList(items: [ListItem(content: [paragraph])]))

            case .divider:
                return existing  // unreachable; handled above
            }
        }

        // After a wrap, the inner leaf's path gains the new outer
        // container's id. Update selection.path so the editor's
        // caret still addresses the leaf where the user's content
        // ended up.
        if let wrapperID = newOuterIDForWrap,
           !selection.path.isEmpty,
           selection.path.last == targetID {
            // Replace the trailing component with [wrapperID, targetID]
            // so the path grows by one level for the new wrapper.
            var newPath = Array(selection.path.dropLast())
            newPath.append(wrapperID)
            newPath.append(targetID)
            selection = BlockTreeSelection(
                path: newPath,
                startUTF16: selection.startUTF16,
                endUTF16: selection.endUTF16
            )
        }
    }

    /// Exit the current list: convert the empty list-item
    /// paragraph at `selection.path` into a body paragraph,
    /// splitting the parent list if the empty item is not at the
    /// end. Returns true if the surgery ran; false if the
    /// selection doesn't point at a list-item leaf (the caller
    /// no-ops in that case so a stale command doesn't dirty the
    /// document).
    ///
    /// **Four cases for `prefix + paragraph + suffix`:**
    ///   - **List has one item, the empty target:** the list
    ///     dissolves entirely, replaced by the paragraph.
    ///   - **Target is the first item:** paragraph emits before
    ///     the surviving list. List keeps the outer container's
    ///     `id` so NoteRegion anchors stay stable on the items
    ///     that didn't move.
    ///   - **Target is the last item:** paragraph emits after
    ///     the surviving list. Same id-stability rule.
    ///   - **Target is in the middle:** the list splits — first
    ///     half keeps the outer id, paragraph between, second
    ///     half gets a fresh id (anchors on items after the
    ///     split need an explicit migration, tracked alongside
    ///     the text-range anchor sweep work).
    ///
    /// The new paragraph reuses the empty leaf's `id` so the
    /// caller's selection (which still names that id) lands on
    /// the paragraph naturally — caret at offset 0, ready to type
    /// body text.
    fileprivate static func exitList(
        document: inout RichTextDocument,
        selection: inout BlockTreeSelection
    ) -> Bool {
        guard let leafID = selection.path.last,
              selection.path.count >= 2 else { return false }
        let containerPath = Array(selection.path.dropLast())
        guard let container = document.block(at: containerPath) else { return false }

        let items: [ListItem]
        let isOrdered: Bool
        switch container.kind {
        case .bulletList(let xs):
            items = xs
            isOrdered = false
        case .orderedList(let xs):
            items = xs
            isOrdered = true
        default:
            return false
        }

        guard let itemIndex = items.firstIndex(where: { item in
            item.content.contains(where: { $0.id == leafID })
        }) else { return false }

        let prefix = Array(items.prefix(itemIndex))
        let suffix = Array(items.suffix(from: itemIndex + 1))
        // Preserve the leaf's actual inline runs (normally empty —
        // the editor only fires exitList on empty items). Hardcoding
        // empty here turned any desynced-selection edge case into
        // silent text loss; carrying the runs makes the surgery safe
        // no matter which leaf the selection names.
        let exitedRuns = items[itemIndex].content
            .first(where: { $0.id == leafID })?
            .kind.inlineRuns ?? []
        let exitedParagraph = Block(id: leafID, kind: .paragraph(inline: exitedRuns))

        var replacements: [Block] = []
        if !prefix.isEmpty {
            // Keep outer container id so the items before the
            // split keep stable identity.
            let kind: Block.Kind = isOrdered
                ? .orderedList(items: prefix)
                : .bulletList(items: prefix)
            replacements.append(Block(id: container.id, kind: kind))
        }
        replacements.append(exitedParagraph)
        if !suffix.isEmpty {
            // Fresh outer id — anchors on these items need
            // migration when text-range NoteRegion ships.
            let kind: Block.Kind = isOrdered
                ? .orderedList(items: suffix)
                : .bulletList(items: suffix)
            replacements.append(Block(id: UUID(), kind: kind))
        }

        document.replaceBlock(id: container.id, with: replacements)

        // Selection lands on the exited paragraph. Path drops the
        // (now-replaced) container id and ends at the paragraph's
        // id (which equals the original leaf id).
        var newPath = containerPath
        newPath.removeLast()
        newPath.append(leafID)
        selection = .insertion(at: newPath, offset: 0)
        return true
    }

    /// Split the leaf at `selection.path` into two leaves at the
    /// cursor (UTF-16 offset = `selection.startUTF16`).
    ///
    /// **Shape per leaf kind:**
    ///   - `paragraph` → splits into `paragraph` + `paragraph`.
    ///   - `heading(level)` → `heading(level)` + `paragraph` —
    ///     Enter on a heading drops back to body text (matches
    ///     Notion / Bear / Apple Notes).
    ///   - `codeBlock` → split into two code blocks, language
    ///     hint preserved on the first half. (Hitting Enter in a
    ///     code block stays in code; Shift-Enter / explicit
    ///     `.applyBody` is how the user exits.)
    ///   - `divider` / container kinds → no-op (the caller
    ///     shouldn't be able to position a cursor there).
    ///
    /// **Container shape:**
    ///   - Inside a list item: replace the original leaf with
    ///     first-half, then insert a NEW list item right after
    ///     containing the second-half leaf. The outer list's
    ///     identity is preserved.
    ///   - Inside a blockquote: insert the new leaf inside the
    ///     same blockquote children, after the original.
    ///   - Top-level: insert the new leaf at the next top-level
    ///     position.
    ///
    /// Returns true on success. False means the selection didn't
    /// point at a leaf that can split (empty path, unresolvable
    /// path, divider). Inline marks survive the split: runs are
    /// carved at the cursor boundary via `splitInlineRuns`, so
    /// splitting bold text mid-run yields two bold halves.
    fileprivate static func insertParagraphAtCursor(
        document: inout RichTextDocument,
        selection: inout BlockTreeSelection
    ) -> Bool {
        guard let leafID = selection.path.last,
              let leaf = document.block(at: selection.path) else { return false }

        let cursorOffset = max(0, selection.startUTF16)

        // First-half leaf retains the original block's kind and id;
        // second-half gets a fresh id. Heading → body paragraph on
        // the second half (matches Notion / Bear / Apple Notes);
        // codeBlock splits into two code blocks, language hint
        // preserved on both.
        let secondID = UUID()
        let firstLeaf: Block
        let secondLeaf: Block
        switch leaf.kind {
        case .paragraph(let inline):
            let (first, second) = splitInlineRuns(inline, atUTF16: cursorOffset)
            firstLeaf = Block(id: leaf.id, kind: .paragraph(inline: first))
            secondLeaf = Block(id: secondID, kind: .paragraph(inline: second))
        case .heading(let level, let inline):
            let (first, second) = splitInlineRuns(inline, atUTF16: cursorOffset)
            firstLeaf = Block(id: leaf.id, kind: .heading(level: level, inline: first))
            secondLeaf = Block(id: secondID, kind: .paragraph(inline: second))
        case .codeBlock(let text, let lang):
            let utf16 = text.utf16
            let split = min(cursorOffset, utf16.count)
            let splitIdx = utf16.index(utf16.startIndex, offsetBy: split)
            let firstText = String(utf16[utf16.startIndex..<splitIdx]) ?? ""
            let secondText = String(utf16[splitIdx..<utf16.endIndex]) ?? ""
            firstLeaf = Block(id: leaf.id, kind: .codeBlock(text: firstText, languageHint: lang))
            secondLeaf = Block(id: secondID, kind: .codeBlock(text: secondText, languageHint: lang))
        case .divider, .bulletList, .orderedList, .blockquote:
            return false
        }

        // Resolve container shape.
        let containerPath = Array(selection.path.dropLast())
        if !containerPath.isEmpty,
           let container = document.block(at: containerPath) {
            switch container.kind {
            case .bulletList(let items), .orderedList(let items):
                guard let itemIndex = items.firstIndex(where: { item in
                    item.content.contains(where: { $0.id == leafID })
                }) else { return false }

                var newItems = items
                newItems[itemIndex] = ListItem(id: items[itemIndex].id, content: [firstLeaf])
                newItems.insert(ListItem(id: UUID(), content: [secondLeaf]), at: itemIndex + 1)

                let isOrdered: Bool
                if case .orderedList = container.kind { isOrdered = true } else { isOrdered = false }
                let newKind: Block.Kind = isOrdered
                    ? .orderedList(items: newItems)
                    : .bulletList(items: newItems)
                document.replaceBlock(
                    id: container.id,
                    with: [Block(id: container.id, kind: newKind)]
                )

                var newPath = containerPath
                newPath.append(secondID)
                selection = .insertion(at: newPath, offset: 0)
                return true

            default:
                break
            }
        }

        // Top-level or blockquote / other container — replace
        // the leaf with first-half, insert second-half after.
        document.replaceLeaf(id: leafID) { _ in firstLeaf }
        document.insertBlock(secondLeaf, afterLeafID: leafID)

        var newPath = Array(selection.path.dropLast())
        newPath.append(secondID)
        selection = .insertion(at: newPath, offset: 0)
        return true
    }

    /// Apply or remove `format` across the selection's UTF-16 range
    /// inside the leaf at `selection.path`. Inline runs are split at
    /// the range boundaries; runs fully covered by the range have the
    /// mark added (or removed if every run in the range already
    /// carries it). Code blocks ignore inline formats.
    fileprivate static func toggleInlineFormat(
        _ format: InlineFormat,
        document: inout RichTextDocument,
        selection: BlockTreeSelection
    ) {
        guard !selection.isInsertion,
              let leafID = selection.path.last else { return }

        let mark = Self.mark(for: format)

        document.mapLeaf(at: selection.path) { leaf in
            guard let runs = leaf.kind.inlineRuns else { return }

            let (rebuilt, _) = applyMarkToInlineRuns(
                runs: runs,
                mark: mark,
                startUTF16: selection.startUTF16,
                endUTF16: selection.endUTF16
            )

            switch leaf.kind {
            case .paragraph:
                leaf.kind = .paragraph(inline: rebuilt)
            case .heading(let level, _):
                leaf.kind = .heading(level: level, inline: rebuilt)
            case .codeBlock, .bulletList, .orderedList, .blockquote, .divider:
                break
            }
            _ = leafID
        }
    }

    /// Internal (not fileprivate): the editor's imperative inline-
    /// toggle surgery (`TextKitEditorView.Coordinator`) maps the same
    /// command vocabulary onto the same Mark — one source of truth for
    /// format → mark.
    static func mark(for format: InlineFormat) -> Mark {
        switch format {
        case .bold:          return .bold
        case .italic:        return .italic
        case .underline:     return .underline
        case .strikethrough: return .strikethrough
        case .code:          return .code
        }
    }

    /// Walk the inline runs, split at the UTF-16 selection boundaries,
    /// and toggle the mark across runs fully covered by the range.
    /// Returns the rebuilt runs and whether the mark was added (true)
    /// or removed (false) — the boolean is informational for tests.
    ///
    /// Toggle direction is determined by whether EVERY covered run
    /// already carries the mark — if so we remove; otherwise we add.
    /// Matches the prior AttributedString-based behavior.
    ///
    /// Internal (not fileprivate): the editor's imperative inline-
    /// toggle surgery reuses this exact logic over runs parsed from
    /// the text storage, so the storage path and the reducer path
    /// cannot drift apart.
    static func applyMarkToInlineRuns(
        runs: [Inline],
        mark: Mark,
        startUTF16: Int,
        endUTF16: Int
    ) -> (rebuilt: [Inline], didAdd: Bool) {
        // First pass: split runs at boundaries. Each output run is
        // tagged with whether it falls inside [start, end).
        struct Slice {
            var text: String
            var marks: [Mark]
            var insideRange: Bool
        }

        var slices: [Slice] = []
        var cursor = 0
        for run in runs {
            let runUTF16Count = run.text.utf16.count
            let runStart = cursor
            let runEnd = cursor + runUTF16Count

            // Carve into 0–3 slices: before-range, in-range,
            // after-range. We use UTF-16 offsets so caret math
            // matches what the editor reports.
            let segments: [(start: Int, end: Int, inside: Bool)] = {
                if runEnd <= startUTF16 || runStart >= endUTF16 {
                    return [(runStart, runEnd, false)]
                }
                var out: [(Int, Int, Bool)] = []
                if runStart < startUTF16 {
                    out.append((runStart, startUTF16, false))
                }
                out.append((max(runStart, startUTF16), min(runEnd, endUTF16), true))
                if runEnd > endUTF16 {
                    out.append((endUTF16, runEnd, false))
                }
                return out
            }()

            let runUTF16 = run.text.utf16
            for (segStart, segEnd, inside) in segments {
                guard segEnd > segStart else { continue }
                let localStart = segStart - runStart
                let localEnd = segEnd - runStart
                let startIdx = runUTF16.index(runUTF16.startIndex, offsetBy: localStart)
                let endIdx = runUTF16.index(runUTF16.startIndex, offsetBy: localEnd)
                let slice = String(decoding: Array(runUTF16[startIdx..<endIdx]), as: UTF16.self)
                if !slice.isEmpty {
                    slices.append(Slice(text: slice, marks: run.marks, insideRange: inside))
                }
            }
            cursor = runEnd
        }

        // Decide toggle direction: ADD if any in-range slice lacks
        // the mark; REMOVE if every in-range slice already has it.
        let inRangeSlices = slices.filter { $0.insideRange }
        let allHave = !inRangeSlices.isEmpty && inRangeSlices.allSatisfy { $0.marks.contains(mark) }
        let didAdd = !allHave

        for index in slices.indices where slices[index].insideRange {
            if didAdd {
                if !slices[index].marks.contains(mark) {
                    slices[index].marks.append(mark)
                }
            } else {
                slices[index].marks.removeAll { $0 == mark }
            }
        }

        // Coalesce adjacent slices with equal marks.
        var rebuilt: [Inline] = []
        for slice in slices {
            if var last = rebuilt.last, last.marks == slice.marks {
                last.text.append(slice.text)
                rebuilt[rebuilt.count - 1] = last
            } else {
                rebuilt.append(Inline(text: slice.text, marks: slice.marks))
            }
        }
        return (rebuilt, didAdd)
    }
}

// MARK: - Block.Kind inline access

extension Block.Kind {
    /// Inline runs for the leaf kinds that carry them. Returns nil
    /// for container kinds and for codeBlock (which is plain text, not
    /// inline runs).
    var inlineRuns: [Inline]? {
        switch self {
        case .paragraph(let inline), .heading(_, let inline):
            return inline
        case .codeBlock, .bulletList, .orderedList, .blockquote, .divider:
            return nil
        }
    }
}

// MARK: - RichTextDocument mutation helpers

extension RichTextDocument {

    /// In-place mutate the leaf block at `path`. The closure receives
    /// the block by `inout`. No-op if the path doesn't resolve.
    mutating func mapLeaf(at path: [UUID], _ transform: (inout Block) -> Void) {
        guard !path.isEmpty else { return }
        var topLevelIndex: Int?
        for (idx, block) in blocks.enumerated() where block.id == path[0] {
            topLevelIndex = idx
            break
        }
        guard let topIdx = topLevelIndex else { return }
        if path.count == 1 {
            transform(&blocks[topIdx])
        } else {
            blocks[topIdx].mapDescendant(at: Array(path.dropFirst()), transform)
        }
    }

    /// Replace the leaf with `id` in-place. The closure receives the
    /// existing block by value and returns the replacement. The new
    /// block's `id` should typically equal the old block's id so
    /// selection paths and NoteRegion anchors keep resolving.
    mutating func replaceLeaf(id: UUID, _ transform: (Block) -> Block) {
        for index in blocks.indices where blocks[index].id == id {
            blocks[index] = transform(blocks[index])
            return
        }
        for index in blocks.indices {
            blocks[index].replaceDescendant(id: id, transform)
        }
    }

    /// Insert `block` immediately after the leaf with `afterLeafID`.
    /// If the leaf is a top-level block, the new block lands at the
    /// next top-level position. If the leaf is nested inside a list
    /// item or blockquote, the new block lands inside the same
    /// container, after the leaf.
    mutating func insertBlock(_ block: Block, afterLeafID: UUID) {
        for index in blocks.indices where blocks[index].id == afterLeafID {
            blocks.insert(block, at: index + 1)
            return
        }
        for index in blocks.indices {
            if blocks[index].insertDescendant(block, after: afterLeafID) {
                return
            }
        }
    }

    /// Replace the block with `id` by an arbitrary sequence of
    /// `replacements`. Used by exit-list surgery, which substitutes
    /// a list container with `[prefix list] + paragraph + [suffix list]`
    /// (any of the three may be absent).
    ///
    /// Like the other helpers, walks top-level blocks first, then
    /// recurses through containers — list items and blockquote
    /// children — so a list nested inside a blockquote can be
    /// replaced in place (the blockquote wrapper stays put,
    /// holding the replacement sequence).
    mutating func replaceBlock(id: UUID, with replacements: [Block]) {
        for index in blocks.indices where blocks[index].id == id {
            blocks.replaceSubrange(index...index, with: replacements)
            return
        }
        for index in blocks.indices {
            if blocks[index].replaceDescendantBlock(id: id, with: replacements) {
                return
            }
        }
    }
}

extension Block {
    /// Mutate the leaf at `path`. Walks direct children for the next
    /// path id; if not found there, recurses through each container
    /// child with the SAME path so deeply nested structures
    /// (blockquote-inside-blockquote, list-inside-blockquote, etc.)
    /// stay reachable. Path convention is the full chain of container
    /// ids from this block to the leaf (skipping ListItem ids per
    /// the §11 ListItem-path-skip rule).
    fileprivate mutating func mapDescendant(at path: [UUID], _ transform: (inout Block) -> Void) {
        guard let next = path.first else { return }
        // Direct-child match (the common case).
        if mapDirectChild(matching: next, remainingPath: path, transform) {
            return
        }
        // Fallback: drill through container children. The path's
        // first id wasn't a direct child, but it might be nested
        // deeper. Recursing with the SAME path lets each container
        // re-check ITS direct children. Used by edge cases where a
        // wrap happened without a path update.
        mapEachContainer { child in
            child.mapDescendant(at: path, transform)
        }
    }

    /// Try to descend through a direct child matching `next`. Returns
    /// true if a child was matched (and transformed); false if no
    /// direct child matches.
    private mutating func mapDirectChild(
        matching next: UUID,
        remainingPath path: [UUID],
        _ transform: (inout Block) -> Void
    ) -> Bool {
        switch kind {
        case .bulletList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == next {
                    if path.count == 1 {
                        transform(&content[j])
                    } else {
                        content[j].mapDescendant(at: Array(path.dropFirst()), transform)
                    }
                    items[i] = ListItem(id: item.id, content: content)
                    kind = .bulletList(items: items)
                    return true
                }
            }
            return false
        case .orderedList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == next {
                    if path.count == 1 {
                        transform(&content[j])
                    } else {
                        content[j].mapDescendant(at: Array(path.dropFirst()), transform)
                    }
                    items[i] = ListItem(id: item.id, content: content)
                    kind = .orderedList(items: items)
                    return true
                }
            }
            return false
        case .blockquote(var children):
            for (i, child) in children.enumerated() where child.id == next {
                if path.count == 1 {
                    transform(&children[i])
                } else {
                    children[i].mapDescendant(at: Array(path.dropFirst()), transform)
                }
                kind = .blockquote(children: children)
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Visit every container child by reference. Used by the
    /// fallback recursion paths in the mutation helpers.
    private mutating func mapEachContainer(_ visit: (inout Block) -> Void) {
        switch kind {
        case .bulletList(var items):
            for i in items.indices {
                var content = items[i].content
                for j in content.indices {
                    visit(&content[j])
                }
                items[i] = ListItem(id: items[i].id, content: content)
            }
            kind = .bulletList(items: items)
        case .orderedList(var items):
            for i in items.indices {
                var content = items[i].content
                for j in content.indices {
                    visit(&content[j])
                }
                items[i] = ListItem(id: items[i].id, content: content)
            }
            kind = .orderedList(items: items)
        case .blockquote(var children):
            for i in children.indices {
                visit(&children[i])
            }
            kind = .blockquote(children: children)
        default:
            break
        }
    }

    fileprivate mutating func replaceDescendant(id: UUID, _ transform: (Block) -> Block) {
        var matched = false
        switch kind {
        case .bulletList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == id {
                    content[j] = transform(child)
                    items[i] = ListItem(id: item.id, content: content)
                    matched = true
                }
            }
            if matched { kind = .bulletList(items: items) }
        case .orderedList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == id {
                    content[j] = transform(child)
                    items[i] = ListItem(id: item.id, content: content)
                    matched = true
                }
            }
            if matched { kind = .orderedList(items: items) }
        case .blockquote(var children):
            for (i, child) in children.enumerated() where child.id == id {
                children[i] = transform(child)
                matched = true
            }
            if matched { kind = .blockquote(children: children) }
        default:
            break
        }
        // Fallback: drill through containers if the id wasn't a
        // direct child of this block. Same correctness rationale as
        // mapDescendant's fallback.
        if !matched {
            mapEachContainer { child in
                child.replaceDescendant(id: id, transform)
            }
        }
    }

    /// Replace the descendant block matching `id` with the given
    /// sequence. Returns true if the substitution ran somewhere
    /// inside this block's subtree. Symmetric with `insertDescendant`
    /// — same container-walking shape, same recursion fallback.
    /// Only `bulletList` / `orderedList` / `blockquote` host nested
    /// blocks at all; everything else returns false immediately.
    fileprivate mutating func replaceDescendantBlock(
        id: UUID,
        with replacements: [Block]
    ) -> Bool {
        switch kind {
        case .bulletList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for j in content.indices where content[j].id == id {
                    content.replaceSubrange(j...j, with: replacements)
                    items[i] = ListItem(id: item.id, content: content)
                    kind = .bulletList(items: items)
                    return true
                }
            }
        case .orderedList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for j in content.indices where content[j].id == id {
                    content.replaceSubrange(j...j, with: replacements)
                    items[i] = ListItem(id: item.id, content: content)
                    kind = .orderedList(items: items)
                    return true
                }
            }
        case .blockquote(var children):
            for i in children.indices where children[i].id == id {
                children.replaceSubrange(i...i, with: replacements)
                kind = .blockquote(children: children)
                return true
            }
        default:
            break
        }
        // Recursion fallback for deeper nesting (list inside
        // blockquote, blockquote inside list item, etc.).
        var replaced = false
        mapEachContainer { child in
            guard !replaced else { return }
            if child.replaceDescendantBlock(id: id, with: replacements) {
                replaced = true
            }
        }
        return replaced
    }

    fileprivate mutating func insertDescendant(_ block: Block, after id: UUID) -> Bool {
        switch kind {
        case .bulletList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == id {
                    content.insert(block, at: j + 1)
                    items[i] = ListItem(id: item.id, content: content)
                    kind = .bulletList(items: items)
                    return true
                }
            }
        case .orderedList(var items):
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == id {
                    content.insert(block, at: j + 1)
                    items[i] = ListItem(id: item.id, content: content)
                    kind = .orderedList(items: items)
                    return true
                }
            }
        case .blockquote(var children):
            for (i, child) in children.enumerated() where child.id == id {
                children.insert(block, at: i + 1)
                kind = .blockquote(children: children)
                return true
            }
        default:
            break
        }
        // Fallback: recurse into containers in case the target id is
        // nested deeper.
        var inserted = false
        mapEachContainer { child in
            guard !inserted else { return }
            if child.insertDescendant(block, after: id) {
                inserted = true
            }
        }
        return inserted
    }
}
