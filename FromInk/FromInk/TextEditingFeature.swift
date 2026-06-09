import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "TextEditingFeature")

/// Owns the state and effects for editing a single text block.
///
/// **Scope.** This feature edits ONE block at a time — the active text
/// block on the current page. Multi-block composition (hybrid pages
/// where multiple text/ink/voice blocks coexist) is handled at the
/// `NotePageFeature` level which scopes a `TextEditingFeature` per
/// active text block.
///
/// **Persistence.** Every body change debounces a `NotebookClient.
/// updateBlockBody` write. Debounce window is 600ms.
///
/// **Encoding.** Body archival routes through `PageBlockSnapshot.
/// encodeBody(_:)` so the encoding path (Path B with `FromInkAttributes`
/// scope) lives in one place. The reducer is encoder-agnostic.
///
/// **Slash command palette.** Scoped under `.slashPalette`; the
/// reducer detects the trigger character in `bodyEdited` (a `/` at
/// the very end of the body, preceded by whitespace or start-of-
/// document) and tracks its offset on `slashPalette.triggerOffset`.
/// Subsequent edits derive the filter slice from the tracked offset
/// instead of re-scanning the body — both a perf win and a bug fix
/// for the multi-`/` case (a later `/` won't jump the anchor).
///
/// **Equality cost.** `AttributedString.Equatable` is O(n). Typical
/// block sizes are <10 KB so per-action diff cost is negligible.
struct TextEditingFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var activeBlock: PageBlockSnapshot? = nil

        /// In-flight edit buffer for the active session. Mirrors
        /// `activeBlock?.body` initially and tracks every keystroke;
        /// the debounced persist effect serializes it back through
        /// the client.
        var editingBody: AttributedString = AttributedString()

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

        case persistRequested
        case persistCompleted
        case persistFailed(reason: String)

        case flush

        /// Apply a block-level format. v1 targets the **last
        /// paragraph** (chars after the last newline) so applying a
        /// heading to an existing multi-paragraph note doesn't
        /// blast the whole document. Selection-aware paragraph
        /// targeting lands with the accessory bar's selection
        /// observer in a later commit.
        case applyBlockFormat(BlockFormat)

        case slashPalette(SlashCommandPaletteFeature.Action)
    }

    enum BlockFormat: Equatable, Sendable {
        case heading(level: Int)   // 1, 2, 3
        case body
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
                state.isDirty = false
                state.lastPersistFailureReason = nil
                state.slashPalette = .init()
                return .cancel(id: Self.persistCancelID)

            case .bodyEdited(let new):
                guard state.loadFailure == nil else { return .none }
                // Read only the LAST character of the prior body —
                // O(1), no full-body allocation.
                let priorLastChar = state.editingBody.characters.last
                state.editingBody = new
                state.isDirty = true

                if let triggerOffset = state.slashPalette.triggerOffset {
                    // Palette is open — validate the trigger
                    // character is still at its tracked offset and
                    // compute the filter slice from there.
                    return handleOpenPaletteBodyEdit(
                        triggerOffset: triggerOffset,
                        new: new
                    )
                } else if shouldOpenPalette(
                    priorLastChar: priorLastChar,
                    current: new
                ) {
                    // `/` was just typed at a word boundary. Capture
                    // its offset so subsequent keystrokes slice the
                    // filter from a stable anchor.
                    let newTriggerOffset = new.characters.count - 1
                    return .merge(
                        schedulePersist(),
                        .send(.slashPalette(.openRequested(
                            triggerOffset: newTriggerOffset
                        )))
                    )
                }
                return schedulePersist()

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
                applyBlockFormat(
                    format,
                    to: &state.editingBody,
                    identity: identity
                )
                state.isDirty = true
                return schedulePersist()

            case .slashPalette(.commandSelected(let command)):
                // Strip the `/<filter>` trigger slice (preserving
                // attributes outside it), then route the command to
                // its handler. Unwired commands no-op gracefully.
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

    /// Handle a body edit while the palette is open. Validates the
    /// trigger character is still at its tracked offset; sends
    /// either `filterChanged` (most common path) or `dismissed`
    /// (trigger consumed by backspace, or a newline / paragraph
    /// break crossed the trigger).
    private func handleOpenPaletteBodyEdit(
        triggerOffset: Int,
        new: AttributedString
    ) -> Effect<Action> {
        let characters = new.characters
        let count = characters.count
        // Body shrank past the trigger — dismiss.
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
        // Trigger character was replaced (e.g. backspaced) —
        // dismiss.
        guard characters[triggerCharIdx] == "/" else {
            return .merge(
                schedulePersist(),
                .send(.slashPalette(.dismissed))
            )
        }
        let filterStart = characters.index(after: triggerCharIdx)
        let filter = String(characters[filterStart...])
        // A newline between trigger and end means the user has
        // moved on past the slash flow — dismiss.
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

    /// True when the most recent edit inserted a `/` that should
    /// trigger the palette. Specifically: the new body ends with `/`,
    /// the prior body did NOT end with `/`, and the character
    /// preceding the `/` is whitespace, newline, or the document
    /// start.
    private func shouldOpenPalette(
        priorLastChar: Character?,
        current: AttributedString
    ) -> Bool {
        let characters = current.characters
        guard let lastChar = characters.last, lastChar == "/" else {
            return false
        }
        guard priorLastChar != "/" else { return false }
        // Inspect the character before the trailing `/`.
        let endIdx = characters.endIndex
        let lastIdx = characters.index(before: endIdx)
        if lastIdx > characters.startIndex {
            let prevIdx = characters.index(before: lastIdx)
            let prev = characters[prevIdx]
            return prev.isWhitespace || prev.isNewline
        }
        // `/` is at position 0 — start of document.
        return true
    }

    /// Strip the `/<filter>` slice from the body, **preserving every
    /// attribute** on the surviving text outside the removed range.
    /// Slices the `AttributedString` directly by index — the prior
    /// implementation round-tripped through `String` and destroyed
    /// every region anchor / highlight / slash-insertion attribute
    /// on the document's surviving text.
    private func stripTriggerSlice(
        from body: inout AttributedString,
        triggerOffset: Int
    ) {
        let characters = body.characters
        guard triggerOffset < characters.count else { return }
        // `AttributedString.CharacterView.Index` IS
        // `AttributedString.Index` (typealias) — we can pass the
        // computed CharacterView index straight to `removeSubrange`
        // without conversion.
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

    /// Maps a `SlashCommand` to the corresponding `applyBlockFormat`
    /// action, or `nil` for commands that aren't wired in this commit.
    private func blockFormatAction(for command: SlashCommand) -> Action? {
        switch command {
        case .heading1:  return .applyBlockFormat(.heading(level: 1))
        case .heading2:  return .applyBlockFormat(.heading(level: 2))
        case .heading3:  return .applyBlockFormat(.heading(level: 3))
        case .body:      return .applyBlockFormat(.body)
        default:         return nil
        }
    }

    /// Applies the requested `PresentationIntent` to the **last
    /// paragraph** of the body — the slice after the last newline.
    /// Single-paragraph bodies get the intent applied to the whole
    /// thing. The `identity` parameter increments per call (from
    /// `State.nextPresentationIdentity`) so TextKit 2's layout
    /// engine doesn't collapse successive headings into one block.
    ///
    /// Caret-aware targeting (apply to the paragraph the user is
    /// actively typing into rather than the last one in the
    /// document) lands with the accessory bar's selection
    /// observer.
    private func applyBlockFormat(
        _ format: BlockFormat,
        to body: inout AttributedString,
        identity: Int
    ) {
        let intent: PresentationIntent
        switch format {
        case .heading(let level):
            intent = PresentationIntent(.header(level: level), identity: identity)
        case .body:
            intent = PresentationIntent(.paragraph, identity: identity)
        }

        // Find the last newline. Apply intent to chars AFTER it
        // (the active paragraph). If no newline, apply to the
        // whole body. `AttributedString.CharacterView.Index` IS
        // `AttributedString.Index` — no conversion needed.
        let characters = body.characters
        let paragraphRange: Range<AttributedString.Index>
        if let lastNewlineIdx = characters.lastIndex(of: "\n") {
            let afterNewlineIdx = characters.index(after: lastNewlineIdx)
            paragraphRange = afterNewlineIdx..<body.endIndex
        } else {
            paragraphRange = body.startIndex..<body.endIndex
        }

        body[paragraphRange].presentationIntent = intent
    }
}
