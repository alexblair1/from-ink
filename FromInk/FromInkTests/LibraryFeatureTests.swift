import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `LibraryFeature.importPDFRequested` — the five
/// branches of the PDF-import flow (success, duplicate, oversized,
/// invalid PDF, access denied). Each test stubs `ImportPDFService` and
/// `NotebookClient` independently and asserts the resulting delegate
/// action, so failures localize to the reducer's routing logic rather
/// than the live services' behavior.
final class LibraryFeatureTests: XCTestCase {

    private let fileURL = URL(fileURLWithPath: "/tmp/test.pdf")

    /// Stable fixed-clock value for snapshot construction. Tests don't
    /// assert specific dates on the produced records — the snapshot
    /// equality assertion uses the same value from the helper below.
    private let fixedDate = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - Fixtures

    private func makeDraft(contentHash: String = "abc123") -> ImportedPDFDraft {
        ImportedPDFDraft(
            title: "Test PDF",
            contentHash: contentHash,
            pageCount: 10,
            byteSize: 1024,
            pdfData: Data([0x25, 0x50, 0x44, 0x46]),   // "%PDF" magic
            thumbnailData: nil
        )
    }

    private func makeSnapshot(
        id: UUID = UUID(),
        contentHash: String = "abc123"
    ) -> ImportedPDFSnapshot {
        ImportedPDFSnapshot(
            id: id,
            title: "Test PDF",
            createdAt: fixedDate,
            modifiedAt: fixedDate,
            lastOpenedAt: nil,
            contentHash: contentHash,
            byteSize: 1024,
            pageCount: 10,
            folderID: nil,
            thumbnailData: nil
        )
    }

    /// Constructs a fully-thrown `NotebookClient` with only the closures
    /// the import path actually invokes overridden. Per the project
    /// convention (CLAUDE.md "Replace the entire dependency...") we
    /// can't mutate a single closure on the dependency — every test
    /// builds the full struct.
    private func makeClient(
        importPDF: @escaping @Sendable (ImportedPDFDraft, UUID?) async throws -> ImportedPDFSnapshot
            = { _, _ in throw CancellationError() },
        fetchPDF: @escaping @Sendable (UUID) async throws -> ImportedPDFSnapshot?
            = { _ in throw CancellationError() }
    ) -> NotebookClient {
        NotebookClient(
            fetchAllNotebooks: { throw CancellationError() },
            fetchNotebook: { _ in throw CancellationError() },
            fetchPage: { _ in throw CancellationError() },
            fetchPagesForNotebook: { _ in throw CancellationError() },
            fetchAllFolders: { throw CancellationError() },
            fetchHistoryForPage: { _ in throw CancellationError() },
            fetchHistoryForNotebook: { _ in throw CancellationError() },
            fetchAllTags: { throw CancellationError() },
            createNotebook: { _, _, _ in throw CancellationError() },
            renameNotebook: { _, _ in throw CancellationError() },
            deleteNotebook: { _ in throw CancellationError() },
            touchNotebookModified: { _ in throw CancellationError() },
            fetchAllPDFs: { throw CancellationError() },
            fetchRecentPDFs: { _ in throw CancellationError() },
            fetchPDF: fetchPDF,
            fetchPDFData: { _ in throw CancellationError() },
            findPDFByContentHash: { _ in throw CancellationError() },
            importPDF: importPDF,
            touchPDFOpened: { _ in throw CancellationError() },
            createPage: { _, _ in throw CancellationError() },
            deletePage: { _ in throw CancellationError() },
            reindexPages: { _, _ in throw CancellationError() },
            transferPage: { _, _, _ in throw CancellationError() },
            saveDrawing: { _, _, _ in throw CancellationError() },
            updateOCR: { _, _ in throw CancellationError() },
            updateTypedText: { _, _ in throw CancellationError() },
            addHeader: { _, _, _ in throw CancellationError() },
            updateHeaderOCR: { _, _ in throw CancellationError() },
            deleteHeader: { _ in throw CancellationError() },
            addLink: { _, _, _, _ in throw CancellationError() },
            updateLink: { _, _ in throw CancellationError() },
            deleteLink: { _ in throw CancellationError() },
            recordHistory: { _, _ in throw CancellationError() },
            updateHistoryStatus: { _, _ in throw CancellationError() },
            createFolder: { _, _ in throw CancellationError() },
            deleteFolder: { _ in throw CancellationError() },
            moveNotebookToFolder: { _, _ in throw CancellationError() },
            createTag: { _, _ in throw CancellationError() },
            addTagToNotebook: { _, _ in throw CancellationError() },
            removeTagFromNotebook: { _, _ in throw CancellationError() }
        )
    }

    // MARK: - Success path

    @MainActor
    func test_importPDFRequested_newPDF_delegatesPdfImportedNotDuplicate() async {
        let draft = makeDraft()
        let inserted = makeSnapshot()

        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = .preview(draft)
            $0.notebookClient = self.makeClient(
                importPDF: { _, _ in inserted }
            )
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImported(inserted, wasDuplicate: false)))
    }

    // MARK: - Duplicate path

    @MainActor
    func test_importPDFRequested_duplicate_resolvesExistingAndDelegatesWasDuplicate() async {
        let draft = makeDraft()
        let existingID = UUID()
        let existing = makeSnapshot(id: existingID)

        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = .preview(draft)
            $0.notebookClient = self.makeClient(
                importPDF: { _, _ in
                    throw NotebookClientError.pdfAlreadyImported(existingID: existingID)
                },
                fetchPDF: { id in id == existingID ? existing : nil }
            )
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImported(existing, wasDuplicate: true)))
    }

    /// Dedup-pointer-but-row-missing race: the client throws
    /// `pdfAlreadyImported(existingID:)` but `fetchPDF` returns nil
    /// (the existing PDF was deleted between the dedup check and the
    /// re-fetch). The reducer must surface this as a generic import
    /// failure rather than silently doing nothing.
    @MainActor
    func test_importPDFRequested_duplicate_existingRowMissing_delegatesPdfImportFailed() async {
        let draft = makeDraft()

        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = .preview(draft)
            $0.notebookClient = self.makeClient(
                importPDF: { _, _ in
                    throw NotebookClientError.pdfAlreadyImported(existingID: UUID())
                },
                fetchPDF: { _ in nil }
            )
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImportFailed(
            message: AppStrings.Library.importPDFInvalidMessage
        )))
    }

    // MARK: - Failure paths

    @MainActor
    func test_importPDFRequested_tooLarge_delegatesPdfImportFailed() async {
        let limit = 500 * 1_024 * 1_024
        let byteCount = 600 * 1_024 * 1_024

        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = ImportPDFService { _ in
                throw ImportPDFError.tooLarge(byteCount: byteCount, limit: limit)
            }
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImportFailed(
            message: AppStrings.Library.importPDFTooLargeMessage(byteCount: byteCount, limit: limit)
        )))
    }

    @MainActor
    func test_importPDFRequested_invalidPDF_delegatesPdfImportFailed() async {
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = ImportPDFService { _ in
                throw ImportPDFError.invalidPDF
            }
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImportFailed(
            message: AppStrings.Library.importPDFInvalidMessage
        )))
    }

    @MainActor
    func test_importPDFRequested_accessDenied_delegatesPdfImportFailed() async {
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = ImportPDFService { _ in
                throw ImportPDFError.accessDenied
            }
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImportFailed(
            message: AppStrings.Library.importPDFAccessDeniedMessage
        )))
    }

    @MainActor
    func test_importPDFRequested_attributesUnavailable_delegatesPdfImportFailed() async {
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.importPDFService = ImportPDFService { _ in
                throw ImportPDFError.attributesUnavailable
            }
        }

        await store.send(.importPDFRequested(fileURL))
        await store.receive(.delegate(.pdfImportFailed(
            message: AppStrings.Library.importPDFAttributesUnavailableMessage
        )))
    }
}
