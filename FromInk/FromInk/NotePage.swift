import CryptoKit
import Foundation
import SwiftData

/// A single page inside a `Notebook`. Pages are the unit of lazy loading —
/// `drawingData` and `thumbnailData` are marked `@Attribute(.externalStorage)`
/// so SwiftData stores them off-row and CloudKit promotes them to `CKAsset`
/// on sync (avoiding the 1 MB per-record limit).
///
/// **Lifecycle responsibilities owned by `NotebookClient`:**
/// - Reindexing siblings after `transferPage(to:at:)`
/// - Updating `Notebook.modifiedAt` when any page mutates
/// - Cascade deletion of children (`headers` / `links` / `history`) is
///   driven by the `@Relationship(deleteRule: .cascade, inverse: ...)`
///   macros declared on `Notebook.pages` (parent side only). The
///   `notebook` back-pointer below is intentionally plain — declaring
///   `@Relationship` on both sides triggers SwiftData's "duplicate
///   inverse" runtime error.
@Model final class NotePage {
    var id: UUID = UUID()
    var index: Int = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Per-page template selection, stored as `CanvasTemplate.rawValue`.
    /// Default matches `CanvasTemplate.none.rawValue` so a row created
    /// without an explicit template reads as no-template rather than
    /// the legacy "blank" sentinel that the renderer never honored.
    var templateName: String = CanvasTemplate.none.rawValue

    // Ink payload — externalStorage promotes to CKAsset on sync.
    // **Legacy.** New code reads ink from `blocks` (PageBlock.drawingData).
    // These fields retire when the CanvasScreen refactor lands (text
    // experience EDD §22.5); no migration — schema bumps directly when
    // the cutover commits.
    @Attribute(.externalStorage)
    var drawingData: Data?

    @Attribute(.externalStorage)
    var thumbnailData: Data?

    // OCR — legacy (see above). New OCR writes live on PageBlock.ocrText
    // per ink block.
    var ocrText: String?
    var ocrUpdatedAt: Date?

    // Typed text (populated when parent Notebook.notebookType == .textNote
    // before the block model lands; the block-aware path writes through
    // PageBlock.bodyData instead).
    var typedText: String?

    // ML cache — legacy. `extractedTextHash` (below) is the block-aware
    // replacement, derived from the per-block content-hash manifest.
    var summaryText: String = ""
    var summaryHash: String = ""

    // MARK: Block model (text experience EDD §5)

    /// Aggregated extracted text composed from per-block payloads in
    /// `sortIndex` order: `text.plainText ∪ ink.ocrText ∪ voice.transcript`.
    /// Drives full-text search, Foundation Models input composition,
    /// and the VoiceOver "read entire page" path. Recomputed on every
    /// block save.
    var extractedText: String? = nil

    /// SHA256 over a manifest of per-block `contentHash` values
    /// (joined by `|` in `sortIndex` order). Drives ML cache
    /// invalidation. A pure reorder still trips the hash so ML output
    /// keyed to old order can refresh; an edit to one block changes
    /// only that block's leaf hash, so delta-aware ML callers can
    /// diff the manifest against the last run.
    var extractedTextHash: String = ""

    // Parent — Step 3 declares the inverse on Notebook.pages
    var notebook: Notebook?

    // Children — these inverse macros are safe here because the child
    // classes do not declare their own @Relationship on `page`.
    @Relationship(deleteRule: .cascade, inverse: \NoteHeader.page)
    var headers: [NoteHeader]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteLink.page)
    var links: [NoteLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteHistoryEntry.page)
    var history: [NoteHistoryEntry]? = []

    /// Unified region records — each at-most-one header text +
    /// at-most-one link destination per region. The legacy `headers`
    /// + `links` arrays remain populated during the consumer
    /// migration; new code writes through `regions` only.
    @Relationship(deleteRule: .cascade, inverse: \NoteRegion.page)
    var regions: [NoteRegion]? = []

    /// Ordered block list — the new authoritative payload container
    /// for hybrid text + ink + voice pages. Block kinds and payload
    /// fields are documented on `PageBlock`. New code writes through
    /// `blocks`; the legacy `drawingData` / `ocrText` / `typedText`
    /// fields above stay populated until the CanvasScreen carve-up
    /// (text experience EDD §22.5), then retire in the same commit
    /// that lands per-block ink rendering.
    @Relationship(deleteRule: .cascade, inverse: \PageBlock.page)
    var blocks: [PageBlock]? = []

    init(
        id: UUID = UUID(),
        index: Int = 0,
        createdAt: Date = Date(),
        templateName: String = CanvasTemplate.none.rawValue,
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.index = index
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.templateName = templateName
        self.notebook = notebook
    }

    /// Recomputes `extractedText` and `extractedTextHash` from the
    /// current `blocks`. Caller is responsible for invoking after any
    /// block save / insert / delete / reorder; the `NotebookClient`
    /// block CRUD methods do this automatically.
    ///
    /// `extractedText` joins per-block payloads (`plainText` for text,
    /// `ocrText` for ink, `transcript` for voice) with newline
    /// separators in `sortIndex` order. `extractedTextHash` is SHA256
    /// over the manifest of per-block `contentHash` values joined by
    /// `|` — a leaf-block content change touches exactly one position
    /// in the manifest; a reorder touches all positions so the hash
    /// reflects ordering changes too.
    func recomputeExtractedAggregates() {
        let ordered = (blocks ?? []).sorted { $0.sortIndex < $1.sortIndex }
        let payloads = ordered.compactMap { block -> String? in
            switch block.kind {
            case .text:  return block.plainText
            case .ink:   return block.ocrText
            case .voice: return block.transcript
            }
        }
        extractedText = payloads.joined(separator: "\n")

        let manifest = ordered.map { $0.contentHash }.joined(separator: "|")
        extractedTextHash = PageBlock.sha256(manifest)
    }
}

// MARK: - Block content hash helper

extension PageBlock {
    /// SHA256 hex digest helper used by per-block `contentHash` and the
    /// page-level manifest aggregate. Hex-encoded so the value persists
    /// cleanly through SwiftData strings and CloudKit `String` fields.
    static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
