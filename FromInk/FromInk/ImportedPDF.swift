import Foundation
import SwiftData

/// An imported PDF — a first-class user document, distinct from
/// `Notebook`. A PDF is not a notebook variant; it has different content
/// (immutable imported bytes, not user-drawn pages), different identity
/// (dedupe by content hash), and different annotations (anchored to PDF
/// page indices via the normalized-bounds `PDFAnnotation` model).
///
/// Named `ImportedPDF` rather than `PDFDocument` so it doesn't collide
/// with `PDFKit.PDFDocument` — the rendering type that the upcoming
/// `PDFFeature` viewer will instantiate from `sourcePDFData`.
///
/// **CloudKit notes:**
/// - Every property has a default or is optional (CloudKit silent-failure
///   prevention).
/// - `sourcePDFData` and `thumbnailData` use `@Attribute(.externalStorage)`
///   so payloads larger than CloudKit's 1 MB record limit auto-promote to
///   `CKAsset`.
/// - `contentHash` is the dedupe key. No `@Attribute(.unique)` (CloudKit
///   constraint); `NotebookClient.importPDF` enforces uniqueness via a
///   pre-insert fetch.
/// - `#Predicate` can't read computed properties — predicates on PDFs go
///   directly against stored fields.
///
/// **Relationships:**
/// - `annotations` are owned (cascade-delete on PDF removal).
/// - `folder` is a back-pointer; the inverse lives on `Folder.pdfs` with
///   `.nullify` so deleting a folder returns its PDFs to the root rather
///   than the bin.
///
/// `PDFAnnotation.pdfDocument` is the inverse of `annotations`; see
/// `PDFAnnotation.swift` for the relationship declaration. The field on
/// `PDFAnnotation` keeps the semantic name `pdfDocument` despite the
/// model rename — the field describes the concept, not the type.
@Model final class ImportedPDF {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Last time the user opened this PDF for viewing. Drives the home
    /// "Recent" sort. Distinct from `modifiedAt` so opening-without-
    /// annotating still bubbles a PDF to the top of Recent. `nil` for
    /// never-opened (newly imported).
    var lastOpenedAt: Date?

    /// SHA-256 hex of `sourcePDFData`. Dedupe key at import time so the
    /// same file picked twice doesn't create two PDF entries.
    var contentHash: String = ""

    /// Byte size of `sourcePDFData` as imported. Cached so size lookups
    /// don't have to materialize the externalStorage blob.
    var byteSize: Int = 0

    /// PDF page count, cached at import.
    var pageCount: Int = 0

    /// CloudKit record ID of the user who imported this PDF. Placeholder
    /// for shared-PDF attribution; nil for single-user records.
    var authorUserID: String?

    @Attribute(.externalStorage) var sourcePDFData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?

    /// Folder membership — plain back-pointer. The inverse on `Folder.pdfs`
    /// carries the `@Relationship` macro + `.nullify` rule.
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \PDFAnnotation.pdfDocument)
    var annotations: [PDFAnnotation]? = []

    init(
        id: UUID = UUID(),
        title: String = "",
        contentHash: String = "",
        pageCount: Int = 0,
        byteSize: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        folder: Folder? = nil
    ) {
        self.id = id
        self.title = title
        self.contentHash = contentHash
        self.pageCount = pageCount
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.folder = folder
    }
}
