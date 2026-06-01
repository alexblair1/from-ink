import Foundation

/// Value-type projection of a `Notebook` with its page list and tags
/// loaded. Page payloads are still lightweight here —
/// `NotePageSnapshot` carries no `drawingData`. Open an individual page
/// via `NotebookClient.fetchPage(_:)` for the heavy
/// `NotePageDetailSnapshot` payload.
///
/// PDF annotations live on `PDFDocument`, not on `Notebook`; this type
/// does not surface them.
struct NotebookDetailSnapshot: Equatable, Sendable {
    let notebook: NotebookSnapshot
    let pages: [NotePageSnapshot]
    let tags: [TagSnapshot]
}

// MARK: - Conversion from @Model

extension NotebookDetailSnapshot {
    init(model: Notebook) {
        self.notebook = NotebookSnapshot(model: model)
        self.pages = (model.pages ?? [])
            .sorted { $0.index < $1.index }
            .map(NotePageSnapshot.init(model:))
        self.tags = (model.tags ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map(TagSnapshot.init(model:))
    }
}
