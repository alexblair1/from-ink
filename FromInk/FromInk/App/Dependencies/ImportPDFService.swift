import ComposableArchitecture
import CryptoKit
import Foundation
import PDFKit
import UIKit
import os

private let log = Logger(subsystem: "com.fromink.app", category: "ImportPDFService")

/// Picks, reads, hashes, and parses a PDF file into an `ImportedPDFDraft`
/// — without touching SwiftData. The TCA boundary that owns:
///
/// 1. Security-scoped URL access (`startAccessingSecurityScopedResource`
///    / `stop...`).
/// 2. Pre-load size guard via `FileManager` attributes (don't allocate a
///    multi-GB Data just to discover we'll reject).
/// 3. SHA-256 of the bytes for dedupe.
/// 4. `PDFKit.PDFDocument` parse for title + page count.
/// 5. First-page thumbnail render (JPEG, q=0.7 — bytes matter; this
///    travels over CloudKit).
///
/// The resulting draft is handed to `NotebookClient.importPDF(draft:)`
/// which performs the SwiftData write. Splitting the side-effectful work
/// from the model write keeps testing straightforward (this dependency
/// can be replaced with a fixture draft in any reducer test).
struct ImportPDFService: Sendable {
    var importPDF: @Sendable (URL) async throws -> ImportedPDFDraft
}

// MARK: - Errors

enum ImportPDFError: Error, Equatable, Sendable {
    /// Security-scoped resource access denied. Rare — usually means
    /// the file moved between picker selection and read.
    case accessDenied
    /// File size exceeds `ImportPDFService.maxAssetBytes`. Surfaces the
    /// actual and limit values so the UI can render a clear message.
    case tooLarge(byteCount: Int, limit: Int)
    /// `PDFKit.PDFDocument(data:)` returned nil — file is not a valid
    /// PDF or is corrupted.
    case invalidPDF
    /// `FileManager.attributesOfItem` failed (file missing, permission
    /// denied). Distinguished from `accessDenied` because the cause
    /// differs.
    case attributesUnavailable
}

extension ImportPDFError {
    /// Human-readable, localized message for the import-failure alert.
    /// Per-case so the UI doesn't have to switch on the enum at every
    /// presentation site.
    var userMessage: String {
        switch self {
        case .accessDenied:
            return AppStrings.Library.importPDFAccessDeniedMessage
        case .tooLarge(let byteCount, let limit):
            return AppStrings.Library.importPDFTooLargeMessage(byteCount: byteCount, limit: limit)
        case .invalidPDF:
            return AppStrings.Library.importPDFInvalidMessage
        case .attributesUnavailable:
            return AppStrings.Library.importPDFAttributesUnavailableMessage
        }
    }
}

// MARK: - Tunables

extension ImportPDFService {
    /// Per-import size threshold. UX-driven, not platform-driven —
    /// Apple's documented per-`CKAsset` ceiling is ~50 GB (verified via
    /// Apple Frameworks Engineer reply on
    /// developer.apple.com/forums/thread/651358, May 2026), far above
    /// any realistic PDF. We cap here to bound:
    ///
    ///   • Memory cost of the in-process PDF parse on iPhone (8 GB RAM
    ///     classes can OOM if other apps are active).
    ///   • Upload time over the user's connection.
    ///   • Consumption of the user's iCloud storage quota.
    ///
    /// 500 MB covers >99% of real-world PDFs (textbooks, scanned
    /// references, multi-volume documents). Above this we surface a
    /// rejection that recommends external compression.
    static let maxAssetBytes: Int = 500 * 1_024 * 1_024

    /// Thumbnail render target. ~200 × 260 at JPEG quality 0.7
    /// produces a card-ready preview at ~10–30 KB. Don't bump the
    /// dimensions without checking the resulting byte cost — these
    /// thumbnails ride CloudKit on every PDF.
    static let thumbnailSize = CGSize(width: 200, height: 260)
    static let thumbnailJPEGQuality: CGFloat = 0.7
}

// MARK: - Live

extension ImportPDFService: DependencyKey {
    static let liveValue = ImportPDFService { url in
        // 1. Security-scoped access. Always paired with stop() via defer.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard scoped else {
            log.error("Security-scoped access denied for \(url.lastPathComponent, privacy: .private)")
            throw ImportPDFError.accessDenied
        }

        // 2. Pre-load size guard. Reading FileManager attributes is
        // cheap; reading bytes for a 1 GB PDF just to reject is not.
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            log.error("File attributes unavailable for \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
            throw ImportPDFError.attributesUnavailable
        }
        let fileSize = (attrs[.size] as? Int) ?? 0
        guard fileSize <= ImportPDFService.maxAssetBytes else {
            log.notice("Rejecting PDF \(url.lastPathComponent, privacy: .private): size=\(fileSize, privacy: .public) exceeds limit=\(ImportPDFService.maxAssetBytes, privacy: .public)")
            throw ImportPDFError.tooLarge(
                byteCount: fileSize,
                limit: ImportPDFService.maxAssetBytes
            )
        }

        // 3. Read bytes. Past the size guard, so worst case is ~500 MB.
        let data = try Data(contentsOf: url)

        // 4. Parse + hash in parallel off the main actor. Parsing a
        // multi-hundred-page PDF and SHA-256-ing 500 MB are both
        // multi-second on iPhone; serializing them was the dominant
        // import latency. Run concurrently — worst case we computed
        // a hash for an invalid PDF (waste but not incorrect).
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        async let parsedPromise = Task.detached(priority: .userInitiated) {
            ParsedPDF.parse(data: data, fallbackTitle: fallbackTitle)
        }.value
        async let hashPromise = Task.detached(priority: .userInitiated) {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
        let (parsed, hash) = await (parsedPromise, hashPromise)

        guard let parsed else {
            log.error("PDFKit failed to parse \(url.lastPathComponent, privacy: .private)")
            throw ImportPDFError.invalidPDF
        }

        log.info("Parsed PDF \(url.lastPathComponent, privacy: .private): pages=\(parsed.pageCount, privacy: .public) bytes=\(data.count, privacy: .public) hash=\(String(hash.prefix(8)), privacy: .public)")

        return ImportedPDFDraft(
            title: parsed.title,
            contentHash: hash,
            pageCount: parsed.pageCount,
            byteSize: data.count,
            pdfData: data,
            thumbnailData: parsed.thumbnailData
        )
    }
}

// MARK: - Test

extension ImportPDFService: TestDependencyKey {
    /// Fails on any access — tests opt in by overriding with
    /// `withDependencies { $0.importPDFService = .preview(...) }`.
    static let testValue = ImportPDFService { _ in
        throw ImportPDFError.invalidPDF
    }

    /// Convenience for previews / TestStore overrides — returns a
    /// caller-supplied draft regardless of the URL.
    static func preview(_ draft: ImportedPDFDraft) -> ImportPDFService {
        ImportPDFService { _ in draft }
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    var importPDFService: ImportPDFService {
        get { self[ImportPDFService.self] }
        set { self[ImportPDFService.self] = newValue }
    }
}

// MARK: - Internal: parsed PDF projection

/// Value-type projection of a parsed `PDFKit.PDFDocument` — extracted so
/// the off-main parse + the SHA-256 hash can both work over the same
/// `Data` snapshot without holding the heavy `PDFDocument` reference
/// across `await` boundaries.
private struct ParsedPDF: Sendable {
    let title: String
    let pageCount: Int
    let thumbnailData: Data?

    static func parse(data: Data, fallbackTitle: String) -> ParsedPDF? {
        guard let doc = PDFKit.PDFDocument(data: data) else { return nil }
        // A PDF with a whitespace-only title (`"   "`) would otherwise
        // pass the `.isEmpty` check and land in the library as a blank
        // card. Trim first, then fall back if the trimmed result is
        // empty.
        let rawTitle = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? ""
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? fallbackTitle : trimmed
        let thumb = doc.page(at: 0)?
            .thumbnail(of: ImportPDFService.thumbnailSize, for: .cropBox)
            .jpegData(compressionQuality: ImportPDFService.thumbnailJPEGQuality)
        return ParsedPDF(
            title: title,
            pageCount: doc.pageCount,
            thumbnailData: thumb
        )
    }
}
