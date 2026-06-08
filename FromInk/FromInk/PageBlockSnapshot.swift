import Foundation

/// Value-type projection of `PageBlock` — the form that crosses the
/// TCA dependency boundary and lives in reducer state.
///
/// **At most one payload field is non-nil**, gated by `kind`:
///   • `.text`  → `body` is non-nil (may be an empty `AttributedString`)
///   • `.ink`   → `drawingData` is non-nil for the active editing block;
///     other ink blocks hold `drawingData == nil` and resolve lazily via
///     the per-block lifecycle (placeholder / thumbnail / live). See
///     text experience EDD §6.4.1.
///   • `.voice` → `voice` is non-nil (audio URL + transcript)
///
/// `body: AttributedString?` is `Equatable` in O(n) over runs and
/// characters — fine for typical block sizes (<10KB). Above 50KB,
/// switch to a hash-based equality wrapper (EDD §5.3 threshold).
struct PageBlockSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageID: UUID
    let sortIndex: Int
    let kind: PageBlockKind
    let heightPoints: Double

    /// `.text` payload — archived body decoded into `AttributedString`.
    let body: AttributedString?

    /// `.ink` payload — `PKDrawing.dataRepresentation()`. Loaded eagerly
    /// only for the currently active or in-viewport ink block; off-
    /// viewport blocks carry nil and resolve through the lifecycle
    /// state machine in `NotePageFeature` (EDD §6.4.1).
    let drawingData: Data?

    /// `.voice` payload — audio file URL + transcript + metadata.
    let voice: VoiceSnapshot?

    /// Cached `ocrText` for ink blocks. Independent of `drawingData`
    /// loading — even an off-viewport ink block exposes its OCR text
    /// for VoiceOver reading order, search, and ML aggregation.
    let ocrText: String?

    /// Cached `plainText` mirror for text blocks (the value the page-
    /// level aggregate manifest hashes).
    let plainText: String?

    let createdAt: Date
    let modifiedAt: Date

    struct VoiceSnapshot: Equatable, Sendable {
        let audioURL: URL?
        let transcript: String
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
        self.pageID = model.page?.id ?? UUID()
        self.sortIndex = model.sortIndex
        self.kind = model.kind
        self.heightPoints = model.heightPoints
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.plainText = model.plainText
        self.ocrText = model.ocrText

        switch model.kind {
        case .text:
            if let data = model.bodyData {
                self.body = PageBlockSnapshot.decodeBody(data)
            } else {
                self.body = AttributedString()
            }
            self.drawingData = nil
            self.voice = nil

        case .ink:
            self.body = nil
            self.drawingData = loadDrawingData ? model.drawingData : nil
            self.voice = nil

        case .voice:
            self.body = nil
            self.drawingData = nil
            self.voice = VoiceSnapshot(
                audioURL: nil,  // resolved in the live capture path; not
                                // synthesized from the @Model row here
                transcript: model.transcript ?? "",
                transcriptConfidence: model.transcriptConfidence,
                durationSeconds: model.audioDurationSeconds,
                language: model.transcriptLanguage
            )
        }
    }

    /// Decodes archived `bodyData` back to `AttributedString`. Prefers
    /// the Codable path (Path B per EDD §7.3); falls back to
    /// `NSKeyedArchiver`-bridged `NSAttributedString` if Codable
    /// decoding fails. Returns an empty `AttributedString` on total
    /// failure so the editor opens to an empty block rather than
    /// crashing on corrupted bytes.
    static func decodeBody(_ data: Data) -> AttributedString {
        if let codable = try? JSONDecoder().decode(AttributedString.self, from: data) {
            return codable
        }
        if let ns = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSAttributedString.self, from: data
        ) {
            return AttributedString(ns)
        }
        return AttributedString()
    }
}
