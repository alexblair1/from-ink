import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `PDFFeature` — the viewer reducer's three
/// load-state transitions (loading → loaded, loading → failed via nil
/// data, loading → failed via throw), the page-change tracking, and
/// the dismiss action. `touchPDFOpened` side effect is verified via
/// a captured ID so a regression that bypasses the recency bump
/// would surface here.
final class PDFFeatureTests: XCTestCase {

    private let pdfID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
    private let bytes = Data([0x25, 0x50, 0x44, 0x46])   // "%PDF" magic — not parsed by the reducer

    private func makeState() -> PDFFeature.State {
        PDFFeature.State(
            pdfID: pdfID,
            title: "Test PDF",
            pageCount: 10
        )
    }

    /// Minimal NotebookClient that only stubs the two closures the
    /// viewer touches. Every other endpoint throws so a regression
    /// that adds a stray call to the viewer's effect would crash the
    /// test loudly.
    private func makeClient(
        fetchPDFData: @escaping @Sendable (UUID) async throws -> Data?
            = { _ in throw CancellationError() },
        touchPDFOpened: @escaping @Sendable (UUID) async throws -> Void
            = { _ in }
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
            fetchPDF: { _ in throw CancellationError() },
            fetchPDFData: fetchPDFData,
            findPDFByContentHash: { _ in throw CancellationError() },
            importPDF: { _, _ in throw CancellationError() },
            touchPDFOpened: touchPDFOpened,
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

    // MARK: - Load: success path

    @MainActor
    func test_onAppear_loadsData_transitionsToLoaded() async {
        let touched = LockIsolated<UUID?>(nil)
        let bytes = self.bytes

        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                fetchPDFData: { _ in bytes },
                touchPDFOpened: { id in touched.setValue(id) }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.onAppear)
        await store.receive(.dataLoaded(bytes)) {
            $0.loadState = .loaded(bytes)
        }

        XCTAssertEqual(touched.value, pdfID, "Opening the viewer must bump lastOpenedAt via touchPDFOpened")
    }

    // MARK: - Load: nil bytes → failed

    @MainActor
    func test_onAppear_nilData_transitionsToFailed() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                fetchPDFData: { _ in nil }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.onAppear)
        await store.receive(.dataLoaded(nil)) {
            $0.loadState = .failed(message: AppStrings.Library.pdfViewerLoadFailedMessage)
        }
    }

    // MARK: - Load: client throws → failed

    @MainActor
    func test_onAppear_clientThrows_transitionsToFailed() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                fetchPDFData: { _ in throw CancellationError() }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.onAppear)
        await store.receive(\.loadFailed) {
            $0.loadState = .failed(message: AppStrings.Library.pdfViewerLoadFailedMessage)
        }
    }

    // MARK: - Page tracking

    @MainActor
    func test_pageChanged_updatesCurrentPage() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.pageChanged(4)) {
            $0.currentPage = 4
        }
    }

    // MARK: - Dismiss

    @MainActor
    func test_dismissTapped_isNoOpInChild_parentHandlesPresentation() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // Child reducer doesn't mutate state on dismiss — the parent
        // (HomeFeature) is what clears the @Presents slot.
        await store.send(.dismissTapped)
    }
}
