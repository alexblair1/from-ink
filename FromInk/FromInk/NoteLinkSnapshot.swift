import Foundation
import CoreGraphics

/// Value-type projection of `NoteLink` — a lasso-selected region of ink
/// flagged as a tappable link. The destination is the union of an
/// external URL or an internal page/notebook reference; exactly one of
/// the three is non-nil in the persisted model.
///
/// Cross-notebook references use UUIDs rather than relationships so that
/// deleting the target notebook leaves a broken link (graceful) rather
/// than cascade-deleting the source page (catastrophic). See
/// `data_model_edd.md` §4.7.
struct NoteLinkSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageID: UUID
    let ocrText: String
    let rect: CGRect
    let createdAt: Date
    let destination: NoteLinkDestination
}

/// The resolved destination of a `NoteLink`. The `NotebookClient` accepts
/// this enum and stores exactly one of the three persisted fields based
/// on the case; the snapshot returns it as a closed value type for
/// pattern matching at the view layer.
enum NoteLinkDestination: Equatable, Sendable, Hashable {
    case external(URL)
    case page(UUID)
    case notebook(UUID)
}

// MARK: - Conversion from @Model

extension NoteLinkSnapshot {
    init(model: NoteLink) {
        self.id = model.id
        self.pageID = model.page?.id ?? UUID()
        self.ocrText = model.ocrText
        self.rect = model.rect
        self.createdAt = model.createdAt
        self.destination = NoteLinkDestination(model: model)
    }
}

extension NoteLinkDestination {
    /// Resolves the stored fields on a `NoteLink` into the closed enum.
    /// External URL takes priority, then page ref, then notebook ref.
    /// If none are set, falls back to `.external(URL?)` with an empty
    /// `about:blank` URL — the persistence layer enforces non-empty
    /// destinations at write time, so this fallback is degenerate.
    init(model: NoteLink) {
        if let raw = model.externalURL, let url = URL(string: raw) {
            self = .external(url)
        } else if let pageID = model.targetPageID {
            self = .page(pageID)
        } else if let notebookID = model.targetNotebookID {
            self = .notebook(notebookID)
        } else {
            self = .external(URL(string: "about:blank")!)
        }
    }
}
