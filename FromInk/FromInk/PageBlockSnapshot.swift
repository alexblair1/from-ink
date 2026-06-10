import Foundation
import os

private let snapshotLog = Logger(subsystem: "com.fromink.app", category: "PageBlockSnapshot")

/// Value-type projection of `PageBlock` — the form that crosses the
/// TCA dependency boundary and lives in reducer state.
///
/// **At most one payload field is non-nil**, gated by `kind`:
///   • `.text`  → `document` is non-nil (may be an empty
///     `RichTextDocument` with `blocks: []`)
///   • `.ink`   → `drawingData` is non-nil for the active editing block;
///     other ink blocks hold `drawingData == nil` and resolve lazily via
///     the per-block lifecycle (placeholder / thumbnail / live). See
///     text experience EDD §6.4.1.
///   • `.voice` → `voice` is non-nil (audio data + transcript)
///
/// `document: RichTextDocument?` is `Equatable` in O(n) over blocks +
/// inline runs — fine for typical block sizes (<10KB). Above 50KB,
/// switch to a hash-based equality wrapper (EDD §5.4 threshold).
///
/// **`pageID: UUID?`** — `nil` signals an orphan block (the back-pointer
/// was dropped, typically a persistence inconsistency). The reducer
/// is expected to surface orphans as a load-failure state rather than
/// fabricating a parent ID.
struct PageBlockSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageID: UUID?
    let sortIndex: Int
    let kind: PageBlockKind
    let heightPoints: Double

    /// `.text` payload — JSON-decoded body as a block-tree document.
    /// `nil` for non-text blocks. May be `RichTextDocument.empty` for
    /// an empty text block; check `bodyDecodeFailed` to distinguish
    /// "empty by content" from "decode failed."
    let document: RichTextDocument?

    /// True when the text block had a non-empty `bodyData` payload but
    /// decoding it failed. The view layer renders a load-failure
    /// placeholder rather than an empty editor in this state. Always
    /// `false` for non-text blocks.
    let bodyDecodeFailed: Bool

    /// `.ink` payload — `PKDrawing.dataRepresentation()`. Loaded eagerly
    /// only for the currently active or in-viewport ink block; off-
    /// viewport blocks carry nil and resolve through the lifecycle
    /// state machine in `NotePageFeature` (EDD §6.4.1).
    let drawingData: Data?

    /// `.voice` payload — audio data + transcript + metadata.
    let voice: VoiceSnapshot?

    /// Cached `ocrText` for ink blocks. Independent of `drawingData`
    /// loading — even an off-viewport ink block exposes its OCR text
    /// for VoiceOver reading order, search, and ML aggregation.
    let ocrText: String?

    /// Cached `plainText` mirror for text blocks (the value the page-
    /// level aggregate manifest hashes).
    let plainText: String?

    /// Per-block content fingerprint. Reducers / callers can compare
    /// this against a freshly fetched snapshot to detect drift (e.g.
    /// an OCR update that landed while the user was scrolled away).
    let contentHash: String

    /// For `.text` blocks created via the voice → transcript flow
    /// (text_experience_edd §18 Scenario C), holds the source voice
    /// block's id so the editor can surface a "play original"
    /// affordance. Nil for all other blocks — including text blocks
    /// the user typed directly.
    let sourceVoiceBlockID: UUID?

    let createdAt: Date
    let modifiedAt: Date

    struct VoiceSnapshot: Equatable, Sendable {
        /// Raw m4a audio bytes. Materialized to a temp file by the
        /// player path before being handed to `AVAudioPlayer`. `nil`
        /// for transcript-only voice blocks (post-capture, audio
        /// optionally cleared to save space).
        let audioData: Data?
        /// `nil` distinguishes "no transcript yet" from "transcript
        /// is empty." Speech recognition can fail or run async; the
        /// reducer surfaces nil as "transcribing…" or "transcript
        /// unavailable" rather than coercing to "".
        let transcript: String?
        let transcriptConfidence: Double
        let durationSeconds: Double
        let language: String?
    }
}

// MARK: - Conversion from @Model

extension PageBlockSnapshot {
    /// Lazy projection — pass `loadDrawingData: false` to skip the
    /// drawing payload for off-viewport ink blocks; pass `true` only
    /// for blocks transitioning to `.live` per the lifecycle state.
    init(model: PageBlock, loadDrawingData: Bool = false) {
        self.id = model.id
        // Orphan blocks (no back-pointer) report nil pageID — the
        // reducer surfaces this as a load-failure state. Fabricating a
        // UUID would mask the inconsistency.
        self.pageID = model.page?.id
        self.sortIndex = model.sortIndex
        self.kind = model.kind
        self.heightPoints = model.heightPoints
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.plainText = model.plainText
        self.ocrText = model.ocrText
        self.contentHash = model.contentHash
        self.sourceVoiceBlockID = model.sourceVoiceBlockID

        switch model.kind {
        case .text:
            let decode = PageBlockSnapshot.decodeBody(model.bodyData, blockID: model.id)
            self.document = decode.document
            self.bodyDecodeFailed = decode.failed
            self.drawingData = nil
            self.voice = nil

        case .ink:
            self.document = nil
            self.bodyDecodeFailed = false
            self.drawingData = loadDrawingData ? model.drawingData : nil
            self.voice = nil

        case .voice:
            self.document = nil
            self.bodyDecodeFailed = false
            self.drawingData = nil
            self.voice = VoiceSnapshot(
                audioData: model.audioData,
                transcript: model.transcript,
                transcriptConfidence: model.transcriptConfidence,
                durationSeconds: model.audioDurationSeconds,
                language: model.transcriptLanguage
            )
        }
    }

    /// Decode an archived `bodyData` blob into a `RichTextDocument`.
    ///
    /// **JSON of RichTextDocument** is the only persistence shape per
    /// text_experience_edd §7.3. Per the 2026-06-09 block-tree pivot
    /// (commit `e2851f4`), the prior AttributedString + Path A/B story
    /// is fully retired. A `nil` or empty data payload yields the
    /// empty document — the editor opens cleanly to its placeholder.
    ///
    /// On decode failure the helper logs (so a corruption never goes
    /// silent in TestFlight) and reports `failed: true` so the snapshot
    /// can carry the state up to the view layer. Returns the empty
    /// document so the editor opens cleanly to the failure placeholder
    /// rather than crashing.
    static func decodeBody(
        _ data: Data?,
        blockID: UUID
    ) -> (document: RichTextDocument, failed: Bool) {
        guard let data, !data.isEmpty else {
            return (.empty, false)
        }
        do {
            let document = try JSONDecoder().decode(RichTextDocument.self, from: data)
            return (document, false)
        } catch {
            snapshotLog.error(
                "Block \(blockID.uuidString, privacy: .public) bodyData failed to decode as RichTextDocument: \(error.localizedDescription, privacy: .public)"
            )
            return (.empty, true)
        }
    }

    /// Encode a `RichTextDocument` into the form that `decodeBody`
    /// expects. The `NotebookClient.updateBlockBody` callers (the text
    /// editor's debounced commit path) reach for this helper rather
    /// than duplicating the encoder configuration at the call site.
    ///
    /// **Sorted-keys encoding.** The encoder uses `.sortedKeys` so
    /// every save produces byte-stable output for a given document.
    /// `PageBlock.contentHash` reads off this stable form; without it
    /// an idempotent save-no-edits-save round-trip would shuffle the
    /// JSON dictionary order and trip the ML cache invalidation.
    static func encodeBody(_ document: RichTextDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(document)
    }
}
