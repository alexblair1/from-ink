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
                Self.applyBlockFormat(format, document: &state.document, selection: state.selection)
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

            case .slashPalette(.commandSelected(let command)):
                if !state.slashPalette.triggerBlockPath.isEmpty,
                   let triggerOffset = state.slashPalette.triggerOffset {
                    Self.stripTriggerSlice(
                        document: &state.document,
                        leafPath: state.slashPalette.triggerBlockPath,
                        triggerOffsetUTF16: triggerOffset
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
    fileprivate static func stripTriggerSlice(
        document: inout RichTextDocument,
        leafPath: [UUID],
        triggerOffsetUTF16: Int
    ) {
        guard let leafID = leafPath.last else { return }
        document.mapLeaf(at: leafPath) { leaf in
            guard let text = leaf.joinedInlineText else { return }
            let utf16 = text.utf16
            guard triggerOffsetUTF16 < utf16.count else { return }
            // Build new inline by walking and dropping everything
            // from the trigger onward.
            let truncated = String(
                decoding: Array(utf16.prefix(triggerOffsetUTF16)),
                as: UTF16.self
            )
            // Replace leaf's inline (paragraph / heading) with a
            // single inline run carrying the prefix; preserves the
            // marks on the surviving prefix only roughly (a more
            // careful implementation would re-walk to preserve
            // per-character marks, but for the slash-strip path the
            // user expected the trailing characters to evaporate).
            switch leaf.kind {
            case .paragraph:
                leaf.kind = .paragraph(inline: truncated.isEmpty ? [] : [Inline(text: truncated)])
            case .heading(let level, _):
                leaf.kind = .heading(level: level, inline: truncated.isEmpty ? [] : [Inline(text: truncated)])
            case .codeBlock(_, let hint):
                leaf.kind = .codeBlock(text: truncated, languageHint: hint)
            case .divider, .bulletList, .orderedList, .blockquote:
                return
            }
            _ = leafID
        }
    }

    /// Apply a block-level format to the leaf at `selection.path`. If
    /// the selection is unset, the document's last leaf is targeted.
    fileprivate static func applyBlockFormat(
        _ format: BlockFormat,
        document: inout RichTextDocument,
        selection: BlockTreeSelection
    ) {
        // Resolve the target leaf — either via the selection's path
        // or the document's last leaf.
        let targetID: UUID
        if !selection.path.isEmpty, let last = selection.path.last {
            targetID = last
        } else if let lastLeaf = document.lastLeafBlock {
            targetID = lastLeaf.id
        } else {
            // Empty document — seed a paragraph then re-target.
            let paragraph = Block(kind: .paragraph(inline: []))
            document.blocks.append(paragraph)
            applyBlockFormat(format, document: &document, selection: .insertion(at: [paragraph.id], offset: 0))
            return
        }

        // For divider, we INSERT a new block after the target rather
        // than replacing it — preserves the user's text and creates
        // a hairline below it.
        if case .divider = format {
            document.insertBlock(
                Block(kind: .divider),
                afterLeafID: targetID
            )
            // Also append a fresh paragraph after the divider so the
            // caret can land on something writable.
            document.insertBlock(
                Block(kind: .paragraph(inline: [])),
                afterLeafID: targetID
            )
            return
        }

        // Other formats replace the target leaf.
        document.replaceLeaf(id: targetID) { existing in
            // Salvage inline runs across the kind change. Code blocks
            // flatten inline runs to plain text (no marks); other
            // kinds preserve marks where possible.
            let existingInline = existing.kind.inlineRuns
            let existingText = existingInline?.reduce(into: "") { $0.append($1.text) } ?? ""

            switch format {
            case .heading(let level):
                return Block(id: existing.id, kind: .heading(level: level, inline: existingInline ?? []))
            case .body:
                return Block(id: existing.id, kind: .paragraph(inline: existingInline ?? []))
            case .blockQuote:
                // Wrap the existing leaf in a blockquote container.
                let wrapped = Block(id: UUID(), kind: existing.kind)
                return Block(id: existing.id, kind: .blockquote(children: [wrapped]))
            case .codeBlock:
                return Block(id: existing.id, kind: .codeBlock(text: existingText, languageHint: nil))
            case .bulletedList:
                let paragraph = Block(id: UUID(), kind: .paragraph(inline: existingInline ?? []))
                return Block(id: existing.id, kind: .bulletList(items: [ListItem(content: [paragraph])]))
            case .numberedList:
                let paragraph = Block(id: UUID(), kind: .paragraph(inline: existingInline ?? []))
                return Block(id: existing.id, kind: .orderedList(items: [ListItem(content: [paragraph])]))
            case .divider:
                return existing  // unreachable; handled above
            }
        }
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

    private static func mark(for format: InlineFormat) -> Mark {
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
    fileprivate static func applyMarkToInlineRuns(
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
}

extension Block {
    fileprivate mutating func mapDescendant(at path: [UUID], _ transform: (inout Block) -> Void) {
        guard let next = path.first else { return }
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
                    return
                }
            }
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
                    return
                }
            }
        case .blockquote(var children):
            for (i, child) in children.enumerated() where child.id == next {
                if path.count == 1 {
                    transform(&children[i])
                } else {
                    children[i].mapDescendant(at: Array(path.dropFirst()), transform)
                }
                kind = .blockquote(children: children)
                return
            }
        default:
            break
        }
    }

    fileprivate mutating func replaceDescendant(id: UUID, _ transform: (Block) -> Block) {
        switch kind {
        case .bulletList(var items):
            var changed = false
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == id {
                    content[j] = transform(child)
                    items[i] = ListItem(id: item.id, content: content)
                    changed = true
                }
            }
            if changed { kind = .bulletList(items: items) }
        case .orderedList(var items):
            var changed = false
            for (i, item) in items.enumerated() {
                var content = item.content
                for (j, child) in content.enumerated() where child.id == id {
                    content[j] = transform(child)
                    items[i] = ListItem(id: item.id, content: content)
                    changed = true
                }
            }
            if changed { kind = .orderedList(items: items) }
        case .blockquote(var children):
            var changed = false
            for (i, child) in children.enumerated() where child.id == id {
                children[i] = transform(child)
                changed = true
            }
            if changed { kind = .blockquote(children: children) }
        default:
            break
        }
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
        return false
    }
}
