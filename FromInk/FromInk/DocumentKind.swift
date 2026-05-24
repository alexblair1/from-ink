import Foundation

/// The document type of a `Notebook`. Stored on `Notebook.documentKindRaw`
/// as a raw `String` (CloudKit cannot encode enums natively) and exposed
/// via the computed `Notebook.documentKind` bridge.
///
/// `#Predicate` cannot read computed properties — predicates on document
/// kind must reference `documentKindRaw == "quickSheet"` directly.
enum DocumentKind: String, Codable, CaseIterable, Sendable {
    /// Multi-page, scrollable notebook with full toolbar.
    case notebook
    /// Single-page quick capture sheet, minimal chrome.
    case quickSheet
    /// PDF with annotation overlay.
    case pdfDocument
    /// Typed text note (keyboard primary).
    case textNote
}
