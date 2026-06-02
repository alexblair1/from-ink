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
                pencilDrawing: nil
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
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
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
            pencilDrawing: nil
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
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
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
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
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
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
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

    private let firstUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private let secondUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // MARK: - Drawing mode

    @MainActor
    func test_drawingModeEntered_resetsToolColorAndTriggers() async {
        var initial = makeState()
        initial.drawingTool = .eraser
        initial.drawingInkColor = .inkRed
        initial.drawingCommitTrigger = DrawingCommitTrigger(id: UUID())
        initial.drawingUndoTrigger = DrawingUndoTrigger(id: UUID(), direction: .undo)

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // Entering resets the tool, color, and any stale triggers so
        // a previous session's residue can't fire.
        await store.send(.drawingModeEntered) {
            $0.isDrawingActive = true
            $0.drawingTool = .pen
            $0.drawingInkColor = .blackText
            $0.drawingCommitTrigger = nil
            $0.drawingUndoTrigger = nil
        }
    }

    @MainActor
    func test_drawingInkColorChanged_whileInactive_isNoOp() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }
        await store.send(.drawingInkColorChanged(.inkRed))
    }

    @MainActor
    func test_drawingInkColorChanged_whileActive_updatesColor() async {
        var initial = makeState()
        initial.isDrawingActive = true

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }
        await store.send(.drawingInkColorChanged(.inkBlue)) {
            $0.drawingInkColor = .inkBlue
        }
    }

    @MainActor
    func test_drawingUndoTapped_whileInactive_isNoOp() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }
        await store.send(.drawingUndoTapped)
    }

    @MainActor
    func test_drawingUndoTapped_whileActive_firesTrigger() async {
        var initial = makeState()
        initial.isDrawingActive = true

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.uuid = .incrementing
        }
        await store.send(.drawingUndoTapped) {
            $0.drawingUndoTrigger = DrawingUndoTrigger(id: self.firstUUID, direction: .undo)
        }
    }

    @MainActor
    func test_drawingRedoTapped_whileActive_firesTrigger() async {
        var initial = makeState()
        initial.isDrawingActive = true

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.uuid = .incrementing
        }
        await store.send(.drawingRedoTapped) {
            $0.drawingUndoTrigger = DrawingUndoTrigger(id: self.firstUUID, direction: .redo)
        }
    }

    @MainActor
    func test_drawingToolChanged_whileInactive_isNoOp() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }
        await store.send(.drawingToolChanged(.eraser))
    }

    @MainActor
    func test_drawingToolChanged_whileActive_updatesTool() async {
        var initial = makeState()
        initial.isDrawingActive = true

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.drawingToolChanged(.eraser)) {
            $0.drawingTool = .eraser
        }
    }

    @MainActor
    func test_drawingDoneTapped_firesCommitTrigger() async {
        var initial = makeState()
        initial.isDrawingActive = true

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.uuid = .incrementing
        }

        await store.send(.drawingDoneTapped) {
            $0.drawingCommitTrigger = DrawingCommitTrigger(id: self.firstUUID)
        }
    }

    @MainActor
    func test_drawingCancelTapped_exitsWithoutCreate() async {
        var initial = makeState()
        initial.isDrawingActive = true
        initial.drawingCommitTrigger = DrawingCommitTrigger(id: UUID())

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.drawingCancelTapped) {
            $0.isDrawingActive = false
            $0.drawingCommitTrigger = nil
        }
    }

    @MainActor
    func test_drawingCommitted_emptyBytes_exitsWithoutCreate() async {
        var initial = makeState()
        initial.isDrawingActive = true

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // Empty drawing — user entered and committed without inking.
        await store.send(.drawingCommitted(bytes: Data(), bounds: .zero, pageIndex: 0)) {
            $0.isDrawingActive = false
            $0.drawingCommitTrigger = nil
        }
    }

    @MainActor
    func test_drawingCommitted_nonEmpty_callsStoreAndAppendsSnapshot() async {
        var initial = makeState()
        initial.isDrawingActive = true
        initial.drawingCommitTrigger = DrawingCommitTrigger(id: UUID())

        let drawingBytes = Data([0xAA, 0xBB, 0xCC])
        let drawingBounds = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3)
        let now = Date(timeIntervalSince1970: 1_780_500_000)
        let snapshot = PDFAnnotationSnapshot(
            id: UUID(), pdfDocumentID: pdfID,
            kind: .pencil, createdAt: now, modifiedAt: now,
            pageIndex: 4, extractedText: "", contents: "",
            bounds: drawingBounds, color: .blackText,
            hasInkData: false, inkDataByteSize: nil,
            pencilDrawing: drawingBytes
        )
        let captured = LockIsolated<(UUID, Int, CGRect, Data, PDFAnnotationColor, Date)?>(nil)

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.calendarContext = .fixed(now: now)
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                createPencil: { pdf, page, bounds, bytes, color, capturedNow in
                    captured.setValue((pdf, page, bounds, bytes, color, capturedNow))
                    return snapshot
                },
                delete: { _ in throw CancellationError() }
            )
        }

        await store.send(.drawingCommitted(
            bytes: drawingBytes, bounds: drawingBounds, pageIndex: 4
        ))
        await store.receive(.drawingSnapshotCreated(snapshot)) {
            $0.annotations = [snapshot]
            $0.isDrawingActive = false
            $0.drawingCommitTrigger = nil
        }

        let call = captured.value!
        XCTAssertEqual(call.0, pdfID)
        XCTAssertEqual(call.1, 4)
        XCTAssertEqual(call.2, drawingBounds)
        XCTAssertEqual(call.3, drawingBytes)
        XCTAssertEqual(call.4, .blackText)
        XCTAssertEqual(call.5, now)
    }

    @MainActor
    func test_drawingCommitted_storeThrows_exitsWithFailure() async {
        var initial = makeState()
        initial.isDrawingActive = true
        initial.drawingCommitTrigger = DrawingCommitTrigger(id: UUID())

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                createPencil: { _, _, _, _, _, _ in
                    throw AnnotationStoreError.pdfNotFound(pdfID: UUID())
                },
                delete: { _ in throw CancellationError() }
            )
        }

        await store.send(.drawingCommitted(
            bytes: Data([0xAA]),
            bounds: CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
            pageIndex: 0
        ))
        await store.receive(.drawingCommitFailed) {
            $0.isDrawingActive = false
            $0.drawingCommitTrigger = nil
        }
    }

    // MARK: - Search

    @MainActor
    func test_searchToggled_opensAndClosesAndClearsState() async {
        var initial = makeState()
        // Simulate a prior session with submitted results so close
        // proves it wipes the whole substate.
        initial.search.status = .results(query: "stale", count: 5, current: 2)
        initial.search.searchTrigger = SearchTrigger(id: UUID(), query: "stale")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.searchToggled) {
            $0.search = PDFSearch()
        }
        await store.send(.searchToggled) {
            $0.search.status = .typing(query: "")
        }
    }

    /// T3 — closing search must reset both triggers back to nil so
    /// the canvas's `lastConsumed*` ids don't keep matching old
    /// triggers across close-reopen.
    @MainActor
    func test_searchToggled_close_resetsBothTriggers() async {
        var initial = makeState()
        initial.search.status = .results(query: "foo", count: 3, current: 1)
        initial.search.searchTrigger = SearchTrigger(id: UUID(), query: "foo")
        initial.search.gotoMatchTrigger = GotoMatchTrigger(id: UUID(), direction: .next)

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.searchToggled) {
            $0.search = PDFSearch()
        }
        XCTAssertNil(store.state.search.searchTrigger)
        XCTAssertNil(store.state.search.gotoMatchTrigger)
    }

    @MainActor
    func test_searchQueryChanged_trimsAndUpdatesTypingStatus() async {
        var initial = makeState()
        initial.search.status = .typing(query: "")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // Trailing whitespace gets stripped at the source so submit
        // and clear-on-empty agree on what's empty.
        await store.send(.searchQueryChanged("hello  ")) {
            $0.search.status = .typing(query: "hello")
        }
        await store.send(.searchQueryChanged("")) {
            $0.search.status = .typing(query: "")
        }
    }

    @MainActor
    func test_searchQueryChanged_whileInactive_isNoOp() async {
        let store = TestStore(initialState: makeState()) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // No `.searchToggled` first — search is inactive. A stray
        // change action shouldn't transition to `.typing`.
        await store.send(.searchQueryChanged("hello"))
    }

    @MainActor
    func test_searchSubmitted_emptyQuery_doesNotFireTrigger() async {
        var initial = makeState()
        initial.search.status = .typing(query: "")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.searchSubmitted)
    }

    @MainActor
    func test_searchSubmitted_firesTriggerAndTransitionsOnResults() async {
        var initial = makeState()
        initial.search.status = .typing(query: "hello")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.uuid = .incrementing
        }

        await store.send(.searchSubmitted) {
            $0.search.searchTrigger = SearchTrigger(id: self.firstUUID, query: "hello")
        }
        await store.send(.searchResultsLoaded(count: 7, currentIndex: 1)) {
            $0.search.status = .results(query: "hello", count: 7, current: 1)
        }
    }

    @MainActor
    func test_searchResultsLoaded_zeroCount_transitionsToNoMatches() async {
        var initial = makeState()
        initial.search.status = .typing(query: "needle")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.searchResultsLoaded(count: 0, currentIndex: 0)) {
            $0.search.status = .noMatches(query: "needle")
        }
    }

    @MainActor
    func test_stepMatch_whileTyping_isNoOp() async {
        var initial = makeState()
        initial.search.status = .typing(query: "foo")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // .typing isn't a results status — stepping has no anchor.
        await store.send(.stepMatch(.next))
    }

    @MainActor
    func test_stepMatch_whileNoMatches_isNoOp() async {
        var initial = makeState()
        initial.search.status = .noMatches(query: "foo")

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        await store.send(.stepMatch(.next))
    }

    @MainActor
    func test_stepMatch_withResults_firesTriggerAndUpdatesCurrent() async {
        var initial = makeState()
        initial.search.status = .results(query: "foo", count: 7, current: 1)

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.uuid = .incrementing
        }

        await store.send(.stepMatch(.next)) {
            $0.search.gotoMatchTrigger = GotoMatchTrigger(id: self.firstUUID, direction: .next)
        }
        await store.send(.currentMatchChanged(2)) {
            $0.search.status = .results(query: "foo", count: 7, current: 2)
        }
    }

    // MARK: - Highlight deletion

    @MainActor
    func test_deleteAnnotation_removesSnapshotOptimisticallyAndCallsStore() async {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let target = PDFAnnotationSnapshot(
            id: UUID(), pdfDocumentID: pdfID,
            kind: .highlight, createdAt: now, modifiedAt: now,
            pageIndex: 1, extractedText: "to delete", contents: "",
            bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
            color: .yellowHighlight,
            hasInkData: false, inkDataByteSize: nil,
            pencilDrawing: nil
        )
        let keep = PDFAnnotationSnapshot(
            id: UUID(), pdfDocumentID: pdfID,
            kind: .highlight, createdAt: now, modifiedAt: now,
            pageIndex: 1, extractedText: "to keep", contents: "",
            bounds: CGRect(x: 0.4, y: 0.2, width: 0.3, height: 0.05),
            color: .yellowHighlight,
            hasInkData: false, inkDataByteSize: nil,
            pencilDrawing: nil
        )
        var initial = makeState()
        initial.annotations = [target, keep]
        let deletedID = LockIsolated<UUID?>(nil)

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
                delete: { id in deletedID.setValue(id) }
            )
        }

        // Optimistic removal happens inside the same reducer pass —
        // assert state in the .send closure.
        await store.send(.deleteAnnotation(target.id)) {
            $0.annotations = [keep]
        }
        await store.receive(.annotationDeleted(target.id))

        XCTAssertEqual(deletedID.value, target.id)
    }

    /// A store-side delete failure restores the snapshot — without
    /// restore the user would see a phantom-deleted highlight until
    /// the viewer reopens (no second `listForPDF` today).
    @MainActor
    func test_deleteAnnotation_storeThrows_restoresSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let target = PDFAnnotationSnapshot(
            id: UUID(), pdfDocumentID: pdfID,
            kind: .highlight, createdAt: now, modifiedAt: now,
            pageIndex: 1, extractedText: "x", contents: "",
            bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
            color: .yellowHighlight,
            hasInkData: false, inkDataByteSize: nil,
            pencilDrawing: nil
        )
        var initial = makeState()
        initial.annotations = [target]

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
                delete: { _ in throw CancellationError() }
            )
        }

        await store.send(.deleteAnnotation(target.id)) {
            $0.annotations = []
        }
        // Failure restores the snapshot at its original sort position.
        await store.receive(.deleteAnnotationFailed(target)) {
            $0.annotations = [target]
        }
    }

    /// Restore inserts at the createdAt-sorted position so the
    /// restored snapshot lands where `listForPDF` would have placed
    /// it — not at the end of the array.
    @MainActor
    func test_deleteAnnotationFailed_restoresAtSortedPosition() async {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        func snap(_ offset: TimeInterval, _ text: String) -> PDFAnnotationSnapshot {
            PDFAnnotationSnapshot(
                id: UUID(), pdfDocumentID: pdfID, kind: .highlight,
                createdAt: now.addingTimeInterval(offset),
                modifiedAt: now.addingTimeInterval(offset),
                pageIndex: 0, extractedText: text, contents: "",
                bounds: .zero, color: .yellowHighlight,
                hasInkData: false, inkDataByteSize: nil,
                pencilDrawing: nil
            )
        }
        let older = snap(0, "older")
        let middle = snap(10, "middle")
        let newer = snap(20, "newer")
        var initial = makeState()
        initial.annotations = [older, newer]

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
        }

        // Restore `middle` directly via the failure action; it should
        // land between `older` and `newer`, not at the end.
        await store.send(.deleteAnnotationFailed(middle)) {
            $0.annotations = [older, middle, newer]
        }
    }

    @MainActor
    func test_deleteAnnotation_unknownID_isNoOpButStillCallsStore() async {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let existing = PDFAnnotationSnapshot(
            id: UUID(), pdfDocumentID: pdfID,
            kind: .highlight, createdAt: now, modifiedAt: now,
            pageIndex: 1, extractedText: "x", contents: "",
            bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
            color: .yellowHighlight,
            hasInkData: false, inkDataByteSize: nil,
            pencilDrawing: nil
        )
        var initial = makeState()
        initial.annotations = [existing]
        let unknownID = UUID()
        let deletedID = LockIsolated<UUID?>(nil)

        let store = TestStore(initialState: initial) {
            PDFFeature()
        } withDependencies: {
            $0.notebookClient = self.makeClient()
            $0.annotationStore = AnnotationStore(
                listForPDF: { _ in [] },
                createHighlight: { _, _, _, _, _, _ in throw CancellationError() },
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
                delete: { id in deletedID.setValue(id) }
            )
        }

        // Unknown id: no removal from state (filter finds nothing), but
        // the store delete still fires — live store treats unknown
        // delete as a no-op (sync race), so this is correct behavior.
        await store.send(.deleteAnnotation(unknownID))
        await store.receive(.annotationDeleted(unknownID))

        XCTAssertEqual(deletedID.value, unknownID)
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
                createPencil: { _, _, _, _, _, _ in throw CancellationError() },
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
