import Foundation
import SwiftData

/// A single block on a `NotePage`. Pages decompose into an ordered
/// sequence of blocks (`text` / `ink` / `voice`); this is the unit of
/// independent storage, OCR, sync, and rendering.
///
/// **Block kinds.** `kindRaw` is the discriminator (see
/// `PageBlockKind`). Each kind owns one payload field:
///   • `.text`  → `bodyData` (archived `AttributedString`)
///   • `.ink`   → `drawingData` (PKDrawing in canonical coords)
///   • `.voice` → `audioData` (m4a) + `transcript`
///
/// Other payload fields stay `nil` for any given block. The application
/// layer enforces the at-most-one invariant (`NotebookClient`); the
/// model has all fields optional with defaults for CloudKit safety.
///
/// **Canonical canvas coords.** Ink strokes are recorded against the
/// notebook's `canonicalCanvasWidth` (Notebook EDD §6.1). The renderer
/// scales at viewport time; no per-stroke transforms touch storage.
///
/// **OCR + ML cache.** `ocrText` is populated by the OCR service for
/// `.ink` blocks. `contentHash` is the per-block fingerprint that feeds
/// the page-level `NotePage.extractedTextHash` aggregate; it covers
/// `plainText` / `ocrText` / `transcript` according to kind. ML cache
/// invalidation reads off the aggregate.
///
/// **Heights.** `heightPoints` is in canonical (canvas) coordinate
/// space, not viewport. Ink blocks expose this as the user-adjustable
/// drag-bar height; text and voice blocks compute it from content and
/// store the last laid-out value as a cache for the block stack.
///
/// **CloudKit notes:**
/// - Every property has a default (data_model_edd §3.2).
/// - All relationships optional.
/// - `@Relationship(...)` declared on the parent (`NotePage.blocks`);
///   this child holds a plain `page` back-pointer — same pattern as
///   `NoteHeader` / `NoteLink` / `NoteRegion`.
/// - Heavy `Data` properties (`bodyData`, `drawingData`, `thumbnailData`,
///   `audioData`) are `@Attribute(.externalStorage)`, auto-promoting
///   to `CKAsset` on sync.
@Model final class PageBlock {
    var id: UUID = UUID()
    var sortIndex: Int = 0
    var kindRaw: String = PageBlockKind.text.rawValue
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Canonical-canvas-space height. For text blocks the layout engine
    /// cache-writes this on every save; for ink blocks the user
    /// adjusts it via the drag bar; for voice blocks the renderer
    /// computes it from waveform + transcript length.
    ///
    /// Default is `PageBlock.defaultHeightPoints` — kind-aware empty-
    /// state heights live in `PageBlock.emptyHeightPoints(for:)` for
    /// reducer-initiated inserts. The 200pt schema default exists for
    /// any caller that constructs a PageBlock without going through
    /// `NotebookClient.insertBlock`.
    var heightPoints: Double = 200

    // MARK: Text payload
    //
    // `bodyData` is intentionally NOT externalStorage. Typical archived
    // AttributedString sizes for a paragraph are 200B–2KB; promoting
    // those to CKAsset on sync would add a per-block asset round-trip
    // for what would otherwise fit inline under CloudKit's 1MB record
    // limit. Ink and voice payloads ARE externalStorage because they're
    // genuinely heavy.
    var bodyData: Data? = nil
    /// Plain-text mirror, recomputed on every text-block save. Drives
    /// `#Predicate` search, ML input composition, and the per-block
    /// `contentHash`.
    var plainText: String? = nil

    // MARK: Ink payload
    @Attribute(.externalStorage) var drawingData: Data? = nil
    @Attribute(.externalStorage) var thumbnailData: Data? = nil
    var ocrText: String? = nil
    var ocrUpdatedAt: Date? = nil

    // MARK: Voice payload
    @Attribute(.externalStorage) var audioData: Data? = nil
    var transcript: String? = nil
    var transcriptConfidence: Double = 0
    var audioDurationSeconds: Double = 0
    /// BCP-47 — the locale active at capture time. Locked so a later
    /// language change doesn't auto-replace authoritative transcript text.
    var transcriptLanguage: String? = nil

    // MARK: Voice → transcript provenance
    /// For `.text` blocks created via the "transcribe this voice block"
    /// flow (text_experience_edd §18 Scenario C), holds the source
    /// voice block's id so the editor can surface a "play original"
    /// affordance next to the transcribed text. Nil for all other
    /// blocks — including text blocks the user typed directly.
    var sourceVoiceBlockID: UUID? = nil

    // MARK: Cache fingerprint
    /// SHA256 of the block's authoritative content (kind-aware):
    /// `.text` → `plainText`, `.ink` → `ocrText`, `.voice` → `transcript`.
    /// `NotePage.extractedTextHash` aggregates these — see
    /// `NotePage.recomputeExtractedTextHash()`.
    var contentHash: String = ""

    // MARK: Parent
    /// Parent back-pointer. Plain (no macro) — the `@Relationship` lives
    /// on `NotePage.blocks` to dodge SwiftData's "duplicate inverse"
    /// runtime error.
    var page: NotePage? = nil

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        sortIndex: Int = 0,
        kind: PageBlockKind = .text,
        heightPoints: Double = PageBlock.defaultHeightPoints,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.page = page
        self.sortIndex = sortIndex
        self.kindRaw = kind.rawValue
        self.heightPoints = heightPoints
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }

    /// Read-only — block kind is immutable post-insert. Changing a
    /// block's kind would orphan the existing payload (e.g. a
    /// `.text → .voice` flip leaves `bodyData` populated on a voice
    /// block). The caller-facing "change kind" operation is
    /// delete + insert, which the EDD §10.4 Pencil-in-blank-text
    /// promotion path uses.
    var kind: PageBlockKind {
        PageBlockKind(rawValue: kindRaw) ?? .text
    }

    // MARK: - Height defaults

    /// Schema-level default height. Falls back to this for callers that
    /// construct a `PageBlock` directly without going through
    /// `NotebookClient.insertBlock`. Reducer-initiated inserts should
    /// use `emptyHeightPoints(for:)` so empty text blocks open at a
    /// single body row rather than a 200pt gap.
    static let defaultHeightPoints: Double = 200

    /// Empty-state height for a freshly inserted block, sized to look
    /// natural before the user has added content.
    ///
    ///   • `.text`  → 44pt — one row of body text at the default
    ///     Dynamic Type size. The TextKit layout immediately overrides
    ///     this with the real measured height once any text exists.
    ///   • `.ink`   → 200pt — the EDD §10.3 floor for ink blocks
    ///     (smaller is a dead zone).
    ///   • `.voice` → 88pt — waveform stub + one-line transcript row.
    static func emptyHeightPoints(for kind: PageBlockKind) -> Double {
        switch kind {
        case .text:  return 44
        case .ink:   return 200
        case .voice: return 88
        }
    }
}
