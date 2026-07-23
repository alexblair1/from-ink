import Foundation

/// Full value-type projection of `NotePage` for the canvas open path —
/// the page's headers/links/history/region snapshots. Block PAYLOADS
/// (ink, text, OCR) are not carried here: the canvas loads them via
/// `fetchBlocksForPage` + `loadBlockDrawing` (hybrid_page_edd §6
/// Phase 2a).
struct NotePageDetailSnapshot: Equatable, Sendable {
    let page: NotePageSnapshot
    let headers: [NoteHeaderSnapshot]
    let links: [NoteLinkSnapshot]
    let history: [NoteHistoryEntrySnapshot]
    /// Unified region records. New canvas rendering reads from this
    /// list; the legacy `headers` / `links` arrays remain populated
    /// for any code still on the old path.
    let regions: [NoteRegionSnapshot]
}

// MARK: - Conversion from @Model

extension NotePageDetailSnapshot {
    init(model: NotePage) {
        self.page = NotePageSnapshot(model: model)
        self.headers = (model.headers ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(NoteHeaderSnapshot.init(model:))
        self.links = (model.links ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map(NoteLinkSnapshot.init(model:))
        self.history = (model.history ?? [])
            .sorted { $0.timestamp > $1.timestamp }
            .map(NoteHistoryEntrySnapshot.init(model:))
        self.regions = (model.regions ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map(NoteRegionSnapshot.init(model:))
    }
}
