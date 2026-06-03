import Foundation

/// How a document arrived at the caller — either by user file picker
/// or by camera scan. The payload that travels with each variant is
/// the consumer's responsibility (file URLs need security scoping,
/// scanned data is freshly assembled and self-contained).
///
/// Lives at the boundary between `DocumentImportFeature` (acquisition)
/// and any caller's destination flow (Home → LibraryFeature → SwiftData).
/// Decoupling the source from the destination is what makes the
/// acquisition feature reusable across Home, Notebook, and any future
/// surface.
///
enum DocumentSource: Equatable, Sendable {
    /// Picked via system file importer. The URL is security-scoped —
    /// the consumer must wrap reads in `startAccessingSecurityScopedResource()`
    /// / `stop...()` per Apple's documentation.
    case file(URL)
    /// Captured via `VNDocumentCameraViewController`. Page count is
    /// surfaced here so callers can render a "Imported N-page scan"
    /// confirmation without inspecting the PDF data.
    case scan(pageCount: Int)
}
