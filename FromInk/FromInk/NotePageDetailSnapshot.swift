import Foundation

/// Full value-type projection of `NotePage` for the canvas open path —
/// includes `drawingData`, OCR text, and the page's headers/links/history
/// snapshots. Reducers pass `drawingData` through to `CanvasView` as
/// `Data?` and never construct a `PKDrawing` themselves; the `Coordinator`
/// owns that translation at the UIKit boundary.
struct NotePageDetailSnapshot: Equatable, Sendable {
    let page: NotePageSnapshot
    let drawingData: Data?
    let ocrText: String?
    let typedText: String?
    let headers: [NoteHeaderSnapshot]
    let links: [NoteLinkSnapshot]
    let history: [NoteHistoryEntrySnapshot]
}

// MARK: - Conversion from @Model

extension NotePageDetailSnapshot {
    init(model: NotePage) {
        self.page = NotePageSnapshot(model: model)
        self.drawingData = model.drawingData
        self.ocrText = model.ocrText
        self.typedText = model.typedText
        self.headers = (model.headers ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(NoteHeaderSnapshot.init(model:))
        self.links = (model.links ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map(NoteLinkSnapshot.init(model:))
        self.history = (model.history ?? [])
            .sorted { $0.timestamp > $1.timestamp }
            .map(NoteHistoryEntrySnapshot.init(model:))
    }
}
