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

    // MARK: - Annotation load

    @MainActor
    func test_onAppear_loadsAnnotations_populatesState() async {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshots: [PDFAnnotationSnapshot] = [
            PDFAnnotationSnapshot(
                id: UUID(), pdfDocumentID: pdfID,
                kind: .highlight, createdAt: now, modifiedAt: now,
                pageIndex: 2,
                extractedText: "matched line",
                contents: "",
                bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
                color: .yellowHighlight,
                hasInkData: false, inkDataByteSize: nil,
                hasPencilDrawing: false, pencilDrawingByteSize: nil
            )
        ]

        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                fetchPDFData: { _ in self.bytes }
            )
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in snapshots },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                delete: { _ in throw CancellationError() }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.onAppear)
        await store.receive(.annotationsLoaded(snapshots)) {
            $0.annotations = snapshots
        }
    }

    // MARK: - Highlight creation

    private let highlightDate = Date(timeIntervalSince1970: 1_780_500_000)

    private func makeLine(
        pageIndex: Int = 2,
        bounds: CGRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
        extractedText: String = "matched line"
    ) -> HighlightLine {
        HighlightLine(pageIndex: pageIndex, bounds: bounds, extractedText: extractedText)
    }

    private func makeSnapshot(
        for line: HighlightLine,
        id: UUID = UUID()
    ) -> PDFAnnotationSnapshot {
        PDFAnnotationSnapshot(
            id: id,
            pdfDocumentID: pdfID,
            kind: .highlight,
            createdAt: highlightDate,
            modifiedAt: highlightDate,
            pageIndex: line.pageIndex,
            extractedText: line.extractedText,
            contents: "",
            bounds: line.bounds,
            color: .yellowHighlight,
            hasInkData: false, inkDataByteSize: nil,
            hasPencilDrawing: false, pencilDrawingByteSize: nil
        )
    }

    @MainActor
    func test_createHighlightFromSelection_emptyArray_isNoOp() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.createHighlightFromSelection([]))
        // No effect, no state change — no follow-up `.highlightCreated`.
    }

    @MainActor
    func test_createHighlightFromSelection_singleLine_callsStoreAndAppends() async {
        let line = makeLine()
        let snapshot = makeSnapshot(for: line)
        let captured = LockIsolated<[(UUID, Int, CGRect, String, PDFAnnotationColor, Date)]>([])

        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.calendarContext = .fixed(now: self.highlightDate)
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { pdfID, pageIndex, bounds, text, color, now in
                    captured.withValue { $0.append((pdfID, pageIndex, bounds, text, color, now)) }
                    return snapshot
                },
                delete: { _ in throw CancellationError() }
            )
        }

        await store.send(.createHighlightFromSelection([line]))
        await store.receive(.highlightCreated(snapshot)) {
            $0.annotations = [snapshot]
        }

        XCTAssertEqual(captured.value.count, 1)
        let call = captured.value[0]
        XCTAssertEqual(call.0, pdfID)
        XCTAssertEqual(call.1, line.pageIndex)
        XCTAssertEqual(call.2, line.bounds)
        XCTAssertEqual(call.3, line.extractedText)
        XCTAssertEqual(call.4, .yellowHighlight)
        XCTAssertEqual(call.5, highlightDate)
    }

    /// A multi-line selection produces one highlight record per line.
    /// State.annotations grows by one on each `.highlightCreated`
    /// receive, in the same order the lines arrived.
    @MainActor
    func test_createHighlightFromSelection_multipleLines_appendsAllInOrder() async {
        let lines = [
            makeLine(pageIndex: 2, extractedText: "first line"),
            makeLine(pageIndex: 2, extractedText: "second line"),
            makeLine(pageIndex: 2, extractedText: "third line")
        ]
        let snapshots = lines.map { makeSnapshot(for: $0) }
        let snapshotQueue = LockIsolated<[PDFAnnotationSnapshot]>(snapshots)

        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.calendarContext = .fixed(now: self.highlightDate)
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, _, _, _ in
                    // Pop the next prearranged snapshot. The reducer's
                    // `for` loop awaits each create before issuing the
                    // next, but `LockIsolated` keeps mutation Sendable-
                    // safe either way.
                    let next = snapshotQueue.withValue { queue -> PDFAnnotationSnapshot? in
                        guard !queue.isEmpty else { return nil }
                        return queue.removeFirst()
                    }
                    guard let next else { throw CancellationError() }
                    return next
                },
                delete: { _ in throw CancellationError() }
            )
        }

        await store.send(.createHighlightFromSelection(lines))
        await store.receive(.highlightCreated(snapshots[0])) {
            $0.annotations = [snapshots[0]]
        }
        await store.receive(.highlightCreated(snapshots[1])) {
            $0.annotations = [snapshots[0], snapshots[1]]
        }
        await store.receive(.highlightCreated(snapshots[2])) {
            $0.annotations = [snapshots[0], snapshots[1], snapshots[2]]
        }
    }

    /// A per-line create failure is logged and skipped — the reducer
    /// continues with the next line so a mid-selection sync hiccup
    /// doesn't drop the entire user gesture.
    @MainActor
    func test_createHighlightFromSelection_storeThrowsForOneLine_continuesWithRest() async {
        let lines = [makeLine(extractedText: "good"), makeLine(extractedText: "bad"), makeLine(extractedText: "good again")]
        let goodSnapshot1 = makeSnapshot(for: lines[0])
        let goodSnapshot2 = makeSnapshot(for: lines[2])

        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.calendarContext = .fixed(now: self.highlightDate)
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, text, _, _ in
                    switch text {
                    case "good": return goodSnapshot1
                    case "bad": throw AnnotationStoreError.pdfNotFound(pdfID: UUID())
                    case "good again": return goodSnapshot2
                    default: throw CancellationError()
                    }
                },
                delete: { _ in throw CancellationError() }
            )
        }

        await store.send(.createHighlightFromSelection(lines))
        // First line succeeds.
        await store.receive(.highlightCreated(goodSnapshot1)) {
            $0.annotations = [goodSnapshot1]
        }
        // Second line throws — logged, no `.highlightCreated`. Reducer
        // moves on.
        // Third line succeeds.
        await store.receive(.highlightCreated(goodSnapshot2)) {
            $0.annotations = [goodSnapshot1, goodSnapshot2]
        }
    }

    /// Annotation load failure is non-fatal — the viewer renders the
    /// PDF without overlay annotations rather than transitioning the
    /// whole loadState to .failed. State.annotations stays empty.
    @MainActor
    func test_onAppear_annotationStoreThrows_leavesAnnotationsEmpty() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient(
                fetchPDFData: { _ in self.bytes }
            )
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in throw CancellationError() },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                delete: { _ in throw CancellationError() }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // No `.annotationsLoaded` action arrives — the listForPDF throw
        // is caught inside `loadAnnotations` and logged, not dispatched.
        // The bytes path still works.
        await store.send(.onAppear)
        await store.receive(.dataLoaded(bytes)) {
            $0.loadState = .loaded(self.bytes)
            // $0.annotations stays []
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
