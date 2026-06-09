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
/// updateBlockBody` write. Debounce window is 600ms — fast enough that
/// a navigate-away within the debounce window flushes via the
/// reducer's `.flush` action; slow enough that rapid typing doesn't
/// thrash SwiftData / CKAsset on every keystroke.
///
/// **Encoding.** Body archival routes through `PageBlockSnapshot.
/// encodeBody(_:)` so the encoding path (Path B with `FromInkAttributes`
/// scope) lives in one place. The reducer is encoder-agnostic.
///
/// **Slash command palette.** Scoped under `.slashPalette`; the
/// reducer detects the trigger character in `bodyEdited` (a `/` at
/// the very end of the body, preceded by whitespace or start-of-
/// document) and forwards selected commands to the format applier.
///
/// **Equality cost.** `AttributedString.Equatable` is O(n). Typical
/// block sizes are <10 KB so per-action diff cost is negligible. The
/// 50 KB threshold from EDD §5.3 hasn't tripped — when it does, the
/// fix is a hash-wrapped equality helper, not an architectural change.
struct TextEditingFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var activeBlock: PageBlockSnapshot? = nil

        /// In-flight edit buffer for the active session. Mirrors
        /// `activeBlock?.body` initially and tracks every keystroke;
        /// the debounced persist effect serializes it back through
        /// the client.
        ///
        /// **Contract:** `editingBody` is the authoritative draft
        /// while editing. `activeBlock.body` is the last-loaded
        /// snapshot from disk — useful for "discard changes" but
        /// never read by the editor itself.
        var editingBody: AttributedString = AttributedString()

        var isDirty: Bool = false

        var loadFailure: LoadFailure? = nil

        var lastPersistFailureReason: String? = nil

        /// Slash command palette state, scoped under this feature so
        /// the trigger detection in `bodyEdited` and the command
        /// dispatch in `slashPalette(.commandSelected)` both live in
        /// the same reducer body.
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

        /// Apply a block-level format to the active paragraph.
        /// Mutates `editingBody`'s `PresentationIntent` for the
        /// paragraph containing the caret (or the whole body if
        /// no selection is tracked yet — v1).
        case applyBlockFormat(BlockFormat)

        case slashPalette(SlashCommandPaletteFeature.Action)
    }

    /// Block formats wired in this commit. The full vocabulary
    /// (blockQuote, code, lists) lands as their handlers ship.
    enum BlockFormat: Equatable, Sendable {
        case heading(level: Int)   // 1, 2, 3
        case body
    }

    @Dependency(\.notebookClient) var notebookClient
    @Dependency(\.continuousClock) var clock

    private static let persistCancelID = "TextEditingFeature.persist"
    private static let debounceMilliseconds: Int = 600

    var body: some Reducer<State, Action> {
        Scope(state: \.slashPalette, action: \.slashPalette) {
            SlashCommandPaletteFeature()
        }

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
                state.slashPalette.isOpen = false
                return .cancel(id: Self.persistCancelID)

            case .bodyEdited(let new):
                guard state.loadFailure == nil else { return .none }
                let priorEnd = String(state.editingBody.characters)
                state.editingBody = new
                state.isDirty = true

                // Slash trigger detection. Open the palette when the
                // newly-typed character is `/` AND it sits at the end
                // of the body AND is preceded by whitespace or start-
                // of-document. Keeps the palette out of in-paragraph
                // `/` insertions (paths, fractions) — matches the
                // EDD §13 "never intercept" rule for ambiguous cases.
                let newChars = String(new.characters)
                if state.slashPalette.isOpen {
                    // Already open — update the filter from the
                    // characters typed AFTER the triggering `/`. We
                    // find the LAST `/` in the new buffer and
                    // everything after it becomes the filter.
                    if let lastSlash = newChars.lastIndex(of: "/") {
                        let filter = String(newChars[newChars.index(after: lastSlash)...])
                        // If the user has navigated past the slash
                        // (backspaced through it or pressed enter
                        // putting whitespace before it), close the
                        // palette.
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
                    } else {
                        // The triggering `/` is gone — dismiss.
                        return .merge(
                            schedulePersist(),
                            .send(.slashPalette(.dismissed))
                        )
                    }
                } else if shouldOpenPalette(prior: priorEnd, current: newChars) {
                    return .merge(
                        schedulePersist(),
                        .send(.slashPalette(.openRequested))
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
                applyBlockFormat(format, to: &state.editingBody)
                state.isDirty = true
                return schedulePersist()

            case .slashPalette(.commandSelected(let command)):
                // Strip the triggering `/<filter>` slice before
                // applying the command so the inserted markup
                // doesn't leave the trigger characters behind.
                stripSlashTrigger(from: &state.editingBody)
                // Route the command to its handler. Only the v1-
                // available block format commands run today; the
                // rest are no-ops at the reducer level (the parent
                // wiring layer will gain handlers as they ship).
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
    }

    // MARK: - Helpers

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

    /// True when the most recent edit inserted a `/` that should
    /// trigger the palette. Specifically: the new body ends with `/`,
    /// the prior body did NOT end with `/`, and the character
    /// preceding the `/` (if any) is whitespace, newline, or the
    /// document start.
    private func shouldOpenPalette(prior: String, current: String) -> Bool {
        guard current.last == "/" else { return false }
        guard prior.last != "/" else { return false }
        // The `/` is the last char; check what's before it.
        let beforeSlash = current.dropLast()
        if let prev = beforeSlash.last {
            return prev.isWhitespace || prev.isNewline
        }
        // `/` is at position 0 — start of document.
        return true
    }

    /// Strips the `/<filter>` slice from the end of the body so the
    /// applied command doesn't leave the trigger characters behind.
    /// Matches the simplest "trigger at end of body" detection in
    /// `shouldOpenPalette`; mid-document triggering is a polish
    /// follow-up.
    private func stripSlashTrigger(from body: inout AttributedString) {
        var chars = String(body.characters)
        guard let lastSlash = chars.lastIndex(of: "/") else { return }
        chars = String(chars[..<lastSlash])
        body = AttributedString(chars)
    }

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

    /// Replaces the active block's body with a representation that
    /// carries the requested `PresentationIntent`. v1 applies the
    /// intent to the whole body — selection-aware paragraph targeting
    /// arrives with the selection observer in the accessory-bar
    /// chrome commit. TextEditor + AttributedString resolve the
    /// intent into visual heading styling natively (iOS 26+ rich
    /// text APIs from WWDC25 session 280).
    private func applyBlockFormat(
        _ format: BlockFormat,
        to body: inout AttributedString
    ) {
        let intent: PresentationIntent
        switch format {
        case .heading(let level):
            intent = PresentationIntent(.header(level: level), identity: 1)
        case .body:
            intent = PresentationIntent(.paragraph, identity: 1)
        }
        let range = body.startIndex..<body.endIndex
        body[range].presentationIntent = intent
    }
}
