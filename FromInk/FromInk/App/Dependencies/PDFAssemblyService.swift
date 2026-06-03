import ComposableArchitecture
import Foundation
import PDFKit
import UIKit
import os

private let log = Logger(subsystem: "com.fromink.app", category: "PDFAssembly")

/// Converts a sequence of scanned page images into a single PDF
/// `Data` blob the rest of the import pipeline can treat as if it
/// came from a file picker. The implementation uses `PDFKit.PDFDocument`
/// with one `PDFPage(image:)` per page — the canonical Apple-blessed
/// path for image-to-PDF.
///
/// Lives as a TCA dependency so:
/// - Tests can stub a deterministic Data blob without invoking real
///   image-encoding machinery (which is `@MainActor`-bound on iOS).
/// - The assembly cost can be observed (`os_signpost` later if we
///   need to chart latency for large multi-page scans).
///
struct PDFAssemblyService: Sendable {
    /// Assemble `pages` into a PDF. Each image becomes one page, in
    /// the order supplied. Throws `PDFAssemblyError.empty` if `pages`
    /// is empty (defensive: VisionKit's scanner shouldn't return a
    /// zero-page scan, but we don't want to land a 0-byte PDF in the
    /// library if it does).
    var assemble: @Sendable ([UIImage]) async throws -> Data
}

// MARK: - Errors

enum PDFAssemblyError: Error, Equatable, Sendable {
    /// Caller supplied an empty page array. Should not happen with
    /// `VNDocumentCameraViewController`; defensive guard against
    /// future call sites.
    case empty
    /// `PDFPage(image:)` returned nil for at least one page —
    /// extremely rare (would mean PDFKit rejected a `UIImage`,
    /// which has happened historically with malformed CGImage
    /// backings). Surfaces as a hard failure so the caller can
    /// re-prompt for a new scan rather than land a partial PDF.
    case pageRenderFailed
    /// `PDFDocument.dataRepresentation()` returned nil. Even rarer
    /// than `pageRenderFailed`. Same caller treatment.
    case serializationFailed
}

// MARK: - Live

extension PDFAssemblyService: DependencyKey {
    static let liveValue = PDFAssemblyService { images in
        guard !images.isEmpty else {
            log.error("assemble called with zero pages")
            throw PDFAssemblyError.empty
        }

        // PDFDocument is reference-typed and constructs on the calling
        // actor. The scan delegate already calls back on the main
        // actor, so no isolation hops needed here — we receive the
        // images on main and produce the Data on main.
        let document = PDFDocument()
        for (index, image) in images.enumerated() {
            guard let page = PDFPage(image: image) else {
                log.error("PDFPage(image:) returned nil for page \(index, privacy: .public)")
                throw PDFAssemblyError.pageRenderFailed
            }
            document.insert(page, at: index)
        }

        guard let data = document.dataRepresentation() else {
            log.error("PDFDocument.dataRepresentation() returned nil for \(images.count, privacy: .public)-page scan")
            throw PDFAssemblyError.serializationFailed
        }

        log.info("Assembled \(images.count, privacy: .public)-page PDF (\(data.count, privacy: .public) bytes)")
        return data
    }
}

// MARK: - Test

extension PDFAssemblyService: TestDependencyKey {
    /// Deterministic minimal PDF for TestStore use — a one-page,
    /// blank PDFDocument serialized once at startup. Tests that
    /// care about the byte content override with their own closure.
    static let testValue = PDFAssemblyService { pages in
        guard !pages.isEmpty else { throw PDFAssemblyError.empty }
        return Self.fixturePDFData
    }

    /// Pre-built single-page blank PDF used by `testValue`. Lazy
    /// `static let` so it's computed once and shared across tests.
    private static let fixturePDFData: Data = {
        let document = PDFDocument()
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, points
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let blank = renderer.image { _ in /* intentionally blank */ }
        if let page = PDFPage(image: blank) {
            document.insert(page, at: 0)
        }
        return document.dataRepresentation() ?? Data()
    }()
}

// MARK: - DependencyValues

extension DependencyValues {
    var pdfAssemblyService: PDFAssemblyService {
        get { self[PDFAssemblyService.self] }
        set { self[PDFAssemblyService.self] = newValue }
    }
}
