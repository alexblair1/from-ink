import ComposableArchitecture
import Foundation
import SwiftUI
import os

private let log = Logger(subsystem: "com.fromink.app", category: "TextEditingFeature")

/// Owns the state and effects for editing a single text block.
///
/// **Scope.** This feature edits ONE block at a time — the active text
/// block on the current page.
///
/// **Persistence.** Every body change debounces a `NotebookClient.
/// updateBlockBody` write. Debounce window is 600ms.
///
/// **Encoding.** Body archival routes through `PageBlockSnapshot.
/// encodeBody(_:)` so the encoding path (Path B with `FromInkAttributes`
/// scope) lives in one place.
///
/// **Selection tracking.** iOS 26's `TextEditor` exposes the user's
/// caret / range selection via a `Binding<AttributedTextSelection>`.
/// We track it on `State.selection` so block / inline format actions
/// can target the active paragraph / selection instead of the whole
/// body. Without selection awareness, applying "Heading 1" to a
/// multi-paragraph note would turn the entire document into headings.
///
/// **Slash command palette.** Scoped under `.slashPalette`; the
/// reducer detects the trigger character in `bodyEdited` and tracks
/// its offset on `slashPalette.triggerOffset`.
///
/// **Equality cost.** `AttributedString.Equatable` is O(n). Typical
/// block sizes are <10 KB so per-action diff cost is negligible.
///
/// **Selection diff cost.** `selectionChanged` fires on every caret
/// movement (per-keystroke + per-tap). The handler mutates only
/// `state.selection` and returns `.none` — no persist scheduled, no
/// derived state recomputed. `AttributedTextSelection` is a small
/// value type (range / insertion point only — no body bytes), so
/// the action loop cost per change is bounded regardless of block
/// size. View invalidation is scoped to the TextEditor binding that
/// reads `state.selection`.
struct TextEditingFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var activeBlock: PageBlockSnapshot? = nil

        var editingBody: AttributedString = AttributedString()

        /// Current caret position or selected range, mirrored from
        /// `TextEditor`'s `selection:` binding. Block / inline format
        /// actions read this to target the user's intent.
        ///
        /// `AttributedTextSelection.Indices` is an enum with two
        /// cases: `.insertionPoint(Index)` for a single caret and
        /// `.ranges(RangeSet<Index>)` for a non-empty (possibly
        /// discontinuous) selection.
        ///
        /// **Default value semantics.** `AttributedTextSelection()`
        /// (the zero-argument init) projects as
        /// `.insertionPoint(body.endIndex)` when queried via
        /// `indices(in:)` — verified on iOS 26. Practical consequence:
        /// applying a block format on a brand-new block where the user
        /// hasn't tapped to position the caret targets the LAST
        /// paragraph, which matches the pre-selection-aware behavior
        /// and is the expected outcome when the user opens a fresh
        /// block and runs a slash command. No special-case fallback
        /// for "unset selection" is needed — `firstSelectionIndex`
        /// returns the endIndex through the normal path.
        var selection: AttributedTextSelection = AttributedTextSelection()

        var isDirty: Bool = false

        var loadFailure: LoadFailure? = nil

        var lastPersistFailureReason: String? = nil

        /// Monotonically-increasing counter used for
        /// `PresentationIntent.identity`. Each block-format
        /// application gets a fresh identity so TextKit 2's layout
        /// engine treats successive headings as separate paragraphs.
        var nextPresentationIdentity: Int = 1

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

        case bodyEdited(AttributedString)

        /// User's caret / range selection changed. Reducer mirrors
        /// `TextEditor`'s `selection:` binding so format actions
        /// target the right span.
        case selectionChanged(AttributedTextSelection)

        case persistRequested
        case persistCompleted
        case persistFailed(reason: String)

        case flush

        /// Apply a block-level format to the paragraph containing the
        /// selection's first index. If selection is unavailable, no-op.
        case applyBlockFormat(BlockFormat)

        /// Toggle an inline format (bold / italic / underline /
        /// strikethrough) over each contiguous range of the current
        /// selection. Insertion-point-only selections no-op (there
        /// is no range to toggle on).
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
        // Reduce runs BEFORE the Scope so the parent's
        // .slashPalette(.commandSelected(_)) handler can read the
        // current `slashPalette.triggerOffset` while it's still set
        // — the child's commandSelected handler clears triggerOffset
        // as part of closing the palette, which would race the
        // parent's strip-trigger logic if the Scope ran first.
        Reduce { state, action in
            switch action {
            case .activeBlockChanged(let snapshot):
                // Two distinct paths:
                //
                // 1. **Same block re-seating.** Almost always a
                //    SwiftData echo of our own persist — NotebookFeature
                //    observes the store, refreshes pages, reloads
                //    blocks, fires .activeBlockChanged with the same
                //    snapshot. The editor's editingBody / selection /
                //    palette are the live source of truth; overwriting
                //    them from the snapshot would jump the caret to
                //    endIndex, blank the slash palette mid-typing, and
                //    reset the dirty flag on edits the user may have
                //    queued since the persist debounce started. Refresh
                //    only the failure state + the activeBlock metadata.
                //
                // 2. **Different block (or first load).** The user
                //    switched pages or opened the screen — reset
                //    everything from the new snapshot.
                if let snapshot,
                   let current = state.activeBlock,
                   snapshot.id == current.id {
                    state.activeBlock = snapshot
                    if snapshot.pageID == nil {
                        state.loadFailure = .orphan
                    } else if snapshot.bodyDecodeFailed {
                        state.loadFailure = .bodyDecodeFailed
                    } else {
                        state.loadFailure = nil
                    }
                    return .none
                }

                if let snapshot {
                    if snapshot.pageID == nil {
                        state.loadFailure = .orphan
                    } else if snapshot.bodyDecodeFailed {
                        state.loadFailure = .bodyDecodeFailed
                    } else {
                        state.loadFailure = nil
                    }
                } else {
                    state.loadFailure = nil
                }
                state.activeBlock = snapshot
                state.editingBody = snapshot?.body ?? AttributedString()
                state.selection = AttributedTextSelection()
                state.isDirty = false
                state.lastPersistFailureReason = nil
                state.slashPalette = .init()
                return .cancel(id: Self.persistCancelID)

            case .bodyEdited(let new):
                guard state.loadFailure == nil else { return .none }
                let priorLastChar = state.editingBody.characters.last
                state.editingBody = new
                state.isDirty = true

                if let triggerOffset = state.slashPalette.triggerOffset {
                    return handleOpenPaletteBodyEdit(
                        triggerOffset: triggerOffset,
                        new: new
                    )
                } else if shouldOpenPalette(
                    priorLastChar: priorLastChar,
                    current: new
                ) {
                    let newTriggerOffset = new.characters.count - 1
                    return .merge(
                        schedulePersist(),
                        .send(.slashPalette(.openRequested(
                            triggerOffset: newTriggerOffset
                        )))
                    )
                }
                return schedulePersist()

            case .selectionChanged(let new):
                state.selection = new
                return .none

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
                let identity = state.nextPresentationIdentity
                state.nextPresentationIdentity += 1
                // Lists need a SECOND identity for the parent
                // (unorderedList / orderedList container). Burn one
                // off the counter so it's unique and won't collide
                // with future paragraph intents.
                let parentIdentity: Int?
                switch format {
                case .bulletedList, .numberedList:
                    parentIdentity = state.nextPresentationIdentity
                    state.nextPresentationIdentity += 1
                default:
                    parentIdentity = nil
                }
                applyBlockFormat(
                    format,
                    to: &state.editingBody,
                    selection: state.selection,
                    identity: identity,
                    parentIdentity: parentIdentity
                )
                state.isDirty = true
                return schedulePersist()

            case .toggleInlineFormat(let format):
                guard state.loadFailure == nil else { return .none }
                toggleInlineFormat(
                    format,
                    in: &state.editingBody,
                    selection: state.selection
                )
                state.isDirty = true
                return schedulePersist()

            case .slashPalette(.commandSelected(let command)):
                if let triggerOffset = state.slashPalette.triggerOffset {
                    stripTriggerSlice(
                        from: &state.editingBody,
                        triggerOffset: triggerOffset
                    )
                }
                let formatAction = blockFormatAction(for: command)
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

    // MARK: - Slash trigger handling

    private func handleOpenPaletteBodyEdit(
        triggerOffset: Int,
        new: AttributedString
    ) -> Effect<Action> {
        let characters = new.characters
        let count = characters.count
        guard triggerOffset < count else {
            return .merge(
                schedulePersist(),
                .send(.slashPalette(.dismissed))
            )
        }
        let triggerCharIdx = characters.index(
            characters.startIndex,
            offsetBy: triggerOffset
        )
        guard characters[triggerCharIdx] == "/" else {
            return .merge(
                schedulePersist(),
                .send(.slashPalette(.dismissed))
            )
        }
        let filterStart = characters.index(after: triggerCharIdx)
        let filter = String(characters[filterStart...])
        if filter.contains(where: { $0.isNewline }) {
            return .merge(
                schedulePersist(),
                .send(.slashPalette(.dismissed))
            )
        }
        return .merge(
            schedulePersist(),
            .send(.slashPalette(.filterChanged(filter)))
        )
    }

    private func shouldOpenPalette(
        priorLastChar: Character?,
        current: AttributedString
    ) -> Bool {
        let characters = current.characters
        guard let lastChar = characters.last, lastChar == "/" else {
            return false
        }
        guard priorLastChar != "/" else { return false }
        let endIdx = characters.endIndex
        let lastIdx = characters.index(before: endIdx)
        if lastIdx > characters.startIndex {
            let prevIdx = characters.index(before: lastIdx)
            let prev = characters[prevIdx]
            return prev.isWhitespace || prev.isNewline
        }
        return true
    }

    private func stripTriggerSlice(
        from body: inout AttributedString,
        triggerOffset: Int
    ) {
        let characters = body.characters
        guard triggerOffset < characters.count else { return }
        let triggerIdx = characters.index(
            characters.startIndex,
            offsetBy: triggerOffset
        )
        body.removeSubrange(triggerIdx..<body.endIndex)
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
        let body = state.editingBody
        return .run { send in
            do {
                let data = try PageBlockSnapshot.encodeBody(body)
                let plain = String(body.characters)
                try await notebookClient.updateBlockBody(blockID, data, plain)
                await send(.persistCompleted)
            } catch {
                await send(.persistFailed(reason: error.localizedDescription))
            }
        }
    }

    // MARK: - Block format application

    private func blockFormatAction(for command: SlashCommand) -> Action? {
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
        // commits — each needs a dependency (custom checklist
        // attribute, NoteRegion text anchor, link sheet, EventKit
        // picker, file picker, SpeechService, PhotosPicker,
        // DispatchFeature integration) that isn't part of this
        // vocabulary-wiring commit.
        default: return nil
        }
    }

    /// Applies the requested `PresentationIntent` to the **paragraph
    /// containing the selection's first index**. Insertion-point and
    /// range selections both target the paragraph at the start.
    ///
    /// When the selection is unset (the default
    /// `AttributedTextSelection()`), `indices(in:)` projects as
    /// `.insertionPoint(body.endIndex)`, so the anchor naturally
    /// resolves to the last paragraph — no special-case fallback
    /// required. See `State.selection` doc comment for the contract.
    ///
    /// `parentIdentity` is only consulted for list formats; the
    /// caller supplies a fresh identity so the unordered / ordered
    /// list container is distinguishable from the listItem itself.
    private func applyBlockFormat(
        _ format: BlockFormat,
        to body: inout AttributedString,
        selection: AttributedTextSelection,
        identity: Int,
        parentIdentity: Int?
    ) {
        let intent: PresentationIntent
        switch format {
        case .heading(let level):
            intent = PresentationIntent(.header(level: level), identity: identity)
        case .body:
            intent = PresentationIntent(.paragraph, identity: identity)
        case .blockQuote:
            intent = PresentationIntent(.blockQuote, identity: identity)
        case .codeBlock:
            intent = PresentationIntent(.codeBlock(languageHint: nil), identity: identity)
        case .bulletedList:
            // First (and for now only) item in a fresh list. The
            // parent container's identity is bumped off the same
            // counter — see the reducer's .applyBlockFormat case.
            intent = PresentationIntent(
                .listItem(ordinal: 1),
                identity: identity,
                parent: PresentationIntent(
                    .unorderedList,
                    identity: parentIdentity ?? identity
                )
            )
        case .numberedList:
            intent = PresentationIntent(
                .listItem(ordinal: 1),
                identity: identity,
                parent: PresentationIntent(
                    .orderedList,
                    identity: parentIdentity ?? identity
                )
            )
        case .divider:
            // A divider is a `.thematicBreak` paragraph — TextKit 2
            // renders it as a horizontal rule. The hosting paragraph
            // can be empty; if it has content, the user invoked
            // `/divider` on a non-empty line and the whole line
            // becomes the rule. v1 caveat — matches the existing
            // "headings replace the host paragraph" semantics.
            intent = PresentationIntent(.thematicBreak, identity: identity)
        }

        let anchor = firstSelectionIndex(in: body, selection: selection)
            ?? body.endIndex
        body[paragraphRange(containing: anchor, in: body)].presentationIntent = intent
    }

    /// Pull the first AttributedString.Index out of the selection,
    /// whether the user has an insertion point or a non-empty range.
    /// Returns nil only in the pathological case where
    /// `indices(in:)` reports `.ranges(_)` with an empty range set —
    /// the default selection projects as `.insertionPoint(endIndex)`
    /// so the nil-coalesce in `applyBlockFormat` is purely defensive.
    private func firstSelectionIndex(
        in body: AttributedString,
        selection: AttributedTextSelection
    ) -> AttributedString.Index? {
        switch selection.indices(in: body) {
        case .insertionPoint(let idx):
            return idx
        case .ranges(let rangeSet):
            return rangeSet.ranges.first?.lowerBound
        }
    }

    /// Compute the range bounded by the previous newline (exclusive)
    /// and the next newline (exclusive) around `anchor`. Used to
    /// target a single paragraph for `applyBlockFormat`.
    private func paragraphRange(
        containing anchor: AttributedString.Index,
        in body: AttributedString
    ) -> Range<AttributedString.Index> {
        let characters = body.characters
        let start: AttributedString.Index
        if let previousNewline = characters[..<anchor].lastIndex(of: "\n") {
            start = characters.index(after: previousNewline)
        } else {
            start = characters.startIndex
        }
        let end: AttributedString.Index
        if let nextNewline = characters[anchor...].firstIndex(of: "\n") {
            end = nextNewline
        } else {
            end = body.endIndex
        }
        return start..<end
    }

    // MARK: - Inline format application

    /// Toggles `format` over every contiguous range of `selection`.
    /// Toggle direction is determined by the format's presence at
    /// the **first character** of the first range — if it's already
    /// applied, the format is removed from all selected ranges;
    /// otherwise it's added.
    ///
    /// Insertion-point-only selections no-op: there's no range to
    /// toggle. A future "format-on-next-character" mode could
    /// extend this; not in v1.
    ///
    /// Bold / italic / strikethrough / code route through
    /// `InlinePresentationIntent` (set-typed, designed for layered
    /// inline emphasis). Underline doesn't live in
    /// `InlinePresentationIntent` — it's a separate
    /// `underlineStyle` attribute (`NSUnderlineStyle`-shaped) on
    /// `AttributedString`. We handle it through that path so the
    /// public `toggleInlineFormat` action covers all four common
    /// formats uniformly to the caller.
    private func toggleInlineFormat(
        _ format: InlineFormat,
        in body: inout AttributedString,
        selection: AttributedTextSelection
    ) {
        let ranges: [Range<AttributedString.Index>]
        switch selection.indices(in: body) {
        case .insertionPoint:
            return
        case .ranges(let rangeSet):
            ranges = Array(rangeSet.ranges)
        }
        guard !ranges.isEmpty else { return }

        switch format {
        case .underline:
            toggleUnderline(in: &body, ranges: ranges)
        case .bold, .italic, .strikethrough, .code:
            toggleInlineIntent(
                intentFor(format),
                in: &body,
                ranges: ranges
            )
        }
    }

    private func toggleInlineIntent(
        _ intent: InlinePresentationIntent,
        in body: inout AttributedString,
        ranges: [Range<AttributedString.Index>]
    ) {
        let firstChar = ranges[0].lowerBound
        let firstCharEnd = body.characters.index(after: firstChar)
        let currentAtStart = body[firstChar..<firstCharEnd].inlinePresentationIntent ?? []
        let toggleOn = !currentAtStart.contains(intent)

        for range in ranges {
            let existing = body[range].inlinePresentationIntent ?? []
            if toggleOn {
                body[range].inlinePresentationIntent = existing.union(intent)
            } else {
                var next = existing
                next.remove(intent)
                if next.isEmpty {
                    body[range].inlinePresentationIntent = nil
                } else {
                    body[range].inlinePresentationIntent = next
                }
            }
        }
    }

    private func toggleUnderline(
        in body: inout AttributedString,
        ranges: [Range<AttributedString.Index>]
    ) {
        let firstChar = ranges[0].lowerBound
        let firstCharEnd = body.characters.index(after: firstChar)
        let currentAtStart = body[firstChar..<firstCharEnd].underlineStyle
        let toggleOn = currentAtStart == nil

        for range in ranges {
            body[range].underlineStyle = toggleOn ? .single : nil
        }
    }

    /// Maps the inline formats that ARE `InlinePresentationIntent`
    /// cases. Underline routes through `underlineStyle` separately.
    private func intentFor(_ format: InlineFormat) -> InlinePresentationIntent {
        switch format {
        case .bold:           return .stronglyEmphasized
        case .italic:         return .emphasized
        case .strikethrough:  return .strikethrough
        case .code:           return .code
        case .underline:
            // Unreachable — callers route underline through
            // `toggleUnderline` directly.
            return []
        }
    }
}
