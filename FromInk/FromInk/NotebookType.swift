import Foundation

/// The variant of a `Notebook`. Stored on `Notebook.notebookTypeRaw` as a
/// raw `String` (CloudKit cannot encode enums natively) and exposed via
/// the computed `Notebook.notebookType` bridge.
///
/// PDFs are NOT a `NotebookType` variant — they're their own root entity
/// (`PDFDocument`). This enum covers only the handwriting/text family of
/// documents that share the `NotePage` + drawing/OCR/template
/// infrastructure.
///
/// `#Predicate` cannot read computed properties — predicates on notebook
/// type must reference `notebookTypeRaw == "quickSheet"` directly.
enum NotebookType: String, Codable, CaseIterable, Sendable {
    /// Multi-page, scrollable notebook with full toolbar.
    case notebook
    /// Single-page quick capture sheet, minimal chrome.
    case quickSheet
    /// Typed text note (keyboard primary).
    case textNote
}
