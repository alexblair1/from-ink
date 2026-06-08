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
    var heightPoints: Double = 200

    // MARK: Text payload
    @Attribute(.externalStorage) var bodyData: Data? = nil
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
        heightPoints: Double = 200
    ) {
        self.id = id
        self.page = page
        self.sortIndex = sortIndex
        self.kindRaw = kind.rawValue
        self.heightPoints = heightPoints
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    var kind: PageBlockKind {
        get { PageBlockKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }
}
