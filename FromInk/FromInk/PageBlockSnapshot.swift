import Foundation
import os

private let snapshotLog = Logger(subsystem: "com.fromink.app", category: "PageBlockSnapshot")

/// Value-type projection of `PageBlock` — the form that crosses the
/// TCA dependency boundary and lives in reducer state.
///
/// **At most one payload field is non-nil**, gated by `kind`:
///   • `.text`  → `body` is non-nil (may be an empty `AttributedString`)
///   • `.ink`   → `drawingData` is non-nil for the active editing block;
///     other ink blocks hold `drawingData == nil` and resolve lazily via
///     the per-block lifecycle (placeholder / thumbnail / live). See
///     text experience EDD §6.4.1.
///   • `.voice` → `voice` is non-nil (audio data + transcript)
///
/// `body: AttributedString?` is `Equatable` in O(n) over runs and
/// characters — fine for typical block sizes (<10KB). Above 50KB,
/// switch to a hash-based equality wrapper (EDD §5.3 threshold).
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

    /// `.text` payload — archived body decoded into `AttributedString`.
    /// `nil` for non-text blocks. May be an empty `AttributedString`
    /// for an empty text block; check `bodyDecodeFailed` to distinguish
    /// "empty by content" from "decode failed."
    let body: AttributedString?

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

        switch model.kind {
        case .text:
            let decode = PageBlockSnapshot.decodeBody(model.bodyData, blockID: model.id)
            self.body = decode.body
            self.bodyDecodeFailed = decode.failed
            self.drawingData = nil
            self.voice = nil

        case .ink:
            self.body = nil
            self.bodyDecodeFailed = false
            self.drawingData = loadDrawingData ? model.drawingData : nil
            self.voice = nil

        case .voice:
            self.body = nil
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

    /// Decode an archived `bodyData` blob into an `AttributedString`.
    ///
    /// **Path B first, Path A fallback.** Per EDD §7.3 the preferred
    /// serialization is `AttributedString.Codable` with the
    /// `FromInkAttributes` scope configuration — that's the native
    /// Swift path through the iOS 26 rich-text `TextEditor` APIs and
    /// our custom attribute keys (region anchor / highlight / slash
    /// insertion) survive the round-trip cleanly. If a payload doesn't
    /// decode as Codable (e.g. an older block archived through the
    /// `NSKeyedArchiver` path before this flipped), we try the
    /// archiver bridge before giving up.
    ///
    /// On total decode failure the helper logs (so a corruption never
    /// goes silent in TestFlight) and reports `failed: true` so the
    /// snapshot can carry the state up to the view layer. Returns an
    /// empty `AttributedString` so the editor opens cleanly to the
    /// failure placeholder rather than crashing.
    static func decodeBody(
        _ data: Data?,
        blockID: UUID
    ) -> (body: AttributedString, failed: Bool) {
        guard let data, !data.isEmpty else {
            return (AttributedString(), false)
        }
        // Path B — Codable with FromInkAttributes scope.
        if let body = try? JSONDecoder().decode(
            AttributedString.self,
            from: data,
            configuration: AttributeScopes.FromInkAttributes.self
        ) {
            return (body, false)
        }
        // Path A — NSKeyedArchiver bridge.
        do {
            if let ns = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSAttributedString.self, from: data
            ) {
                return (AttributedString(ns), false)
            }
            snapshotLog.error(
                "Block \(blockID.uuidString, privacy: .public) bodyData decoded as nil under both Path B and Path A"
            )
            return (AttributedString(), true)
        } catch {
            snapshotLog.error(
                "Block \(blockID.uuidString, privacy: .public) body decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return (AttributedString(), true)
        }
    }

    /// Encode an `AttributedString` into the form that `decodeBody`
    /// expects. Uses Path B (Codable + `FromInkAttributes` scope). The
    /// `NotebookClient.updateBlockBody` callers (the text editor's
    /// debounced commit path) reach for this helper rather than
    /// duplicating the encoder configuration at the call site.
    ///
    /// Errors: encoding can fail if a custom attribute value isn't
    /// `Codable`-conformant. All v1 attribute values (`UUID`,
    /// `HighlightKind`, `SlashCommandID`) are `Codable`, so a thrown
    /// error here indicates a future attribute key was added to the
    /// scope without a `CodableAttributedStringKey` conformance.
    static func encodeBody(_ body: AttributedString) throws -> Data {
        try JSONEncoder().encode(
            body,
            configuration: AttributeScopes.FromInkAttributes.self
        )
    }
}
