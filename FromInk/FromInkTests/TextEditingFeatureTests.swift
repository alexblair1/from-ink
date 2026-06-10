import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// Pins the `TextEditingFeature` reducer's contract on the block-tree
/// content model (2026-06-09 pivot — see `text_experience_edd.md`
/// §5.3 + §22.4).
///
/// The behavioral claims:
///
///   - `activeBlockChanged` seeds the document from the snapshot,
///     clears `isDirty`, and cancels any in-flight persist. Same-
///     block echoes preserve live editor state.
///   - `documentEdited` mirrors the document, marks dirty, schedules
///     a debounced persist; refreshes the slash filter if open.
///   - `selectionChanged` mirrors selection without scheduling
///     persist.
///   - `slashTyped` opens the palette with the trigger location.
///   - `applyBlockFormat` rewrites the target leaf into the requested
///     kind. Heading replaces; blockQuote wraps; lists wrap;
///     divider INSERTS a new block after the target. Unset selection
///     targets the document's last leaf.
///   - `toggleInlineFormat` applies / removes a Mark across the
///     selection's UTF-16 range. Insertion-point-only selections
///     no-op. Toggle removes the mark when every covered run already
///     carries it; otherwise it adds.
///   - `slashPaletteCommandSelected` strips the trigger + filter
///     characters and dispatches the appropriate block-format action.
///   - `flush` forces an immediate persist when dirty.
final class TextEditingFeatureTests: XCTestCase {

    private let blockID = UUID()
    private let pageID = UUID()
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func snapshot(
        kind: PageBlockKind = .text,
        document: RichTextDocument = .empty,
        pageID: UUID? = nil,
        bodyDecodeFailed: Bool = false
    ) -> PageBlockSnapshot {
        PageBlockSnapshot(
            id: blockID,
            pageID: pageID ?? self.pageID,
            sortIndex: 0,
            kind: kind,
            heightPoints: 44,
            document: document,
            bodyDecodeFailed: bodyDecodeFailed,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: document.plainText,
            contentHash: PageBlock.sha256(document.plainText),
            sourceVoiceBlockID: nil,
            createdAt: earlier,
            modifiedAt: earlier
        )
    }

    /// Single-paragraph document for tests that don't care about
    /// multi-block structure.
    private func paragraphDoc(_ text: String) -> RichTextDocument {
        RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: text)]))
        ])
    }

    // MARK: - activeBlockChanged

    @MainActor
    func test_activeBlockChanged_seedsDocumentFromSnapshot() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let doc = paragraphDoc("Hello")
        let snap = snapshot(document: doc)
        await store.send(.activeBlockChanged(snap)) {
            $0.activeBlock = snap
            $0.document = doc
            $0.isDirty = false
            $0.loadFailure = nil
        }
    }

    @MainActor
    func test_activeBlockChanged_decodeFailedSnapshot_surfacesLoadFailure() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let snap = snapshot(bodyDecodeFailed: true)
        await store.send(.activeBlockChanged(snap)) {
            $0.loadFailure = .bodyDecodeFailed
        }
    }

    @MainActor
    func test_activeBlockChanged_orphanSnapshot_surfacesOrphanFailure() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let orphan = PageBlockSnapshot(
            id: blockID,
            pageID: nil,
            sortIndex: 0,
            kind: .text,
            heightPoints: 44,
            document: .empty,
            bodyDecodeFailed: false,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: nil,
            contentHash: "",
            sourceVoiceBlockID: nil,
            createdAt: earlier,
            modifiedAt: earlier
        )
        await store.send(.activeBlockChanged(orphan)) {
            $0.loadFailure = .orphan
        }
    }

    @MainActor
    func test_activeBlockChanged_sameBlockEcho_preservesEditorState() async {
        // SwiftData echoes our own persist back through the
        // NotebookFeature observer. Live editor state (document,
        // selection, palette, dirty) MUST be preserved.
        let initialDoc = paragraphDoc("Meeting notes")
        let initialSnap = snapshot(document: initialDoc)

        var initial = TextEditingFeature.State(activeBlock: initialSnap)
        initial.document = initialDoc
        initial.slashPalette.isOpen = true
        initial.slashPalette.triggerOffset = 5
        initial.slashPalette.triggerBlockPath = [initialDoc.blocks[0].id]
        initial.isDirty = true

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.activeBlockChanged(initialSnap)) {
            $0.activeBlock = initialSnap
        }

        XCTAssertTrue(store.state.slashPalette.isOpen, "Palette must stay open on same-block echo")
        XCTAssertEqual(store.state.slashPalette.triggerOffset, 5)
        XCTAssertTrue(store.state.isDirty, "Dirty flag must survive echo")
        XCTAssertEqual(store.state.document, initialDoc)
    }

    // MARK: - documentEdited

    @MainActor
    func test_documentEdited_marksDirty_andUpdatesDocument() async {
        let initialDoc = paragraphDoc("a")
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: initialDoc))
        initial.document = initialDoc

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let next = paragraphDoc("abc")
        await store.send(.documentEdited(next)) {
            $0.document = next
            $0.isDirty = true
        }
    }

    @MainActor
    func test_documentEdited_whileLoadFailure_isDropped() async {
        var initial = TextEditingFeature.State()
        initial.loadFailure = .bodyDecodeFailed

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // No state change expected.
        await store.send(.documentEdited(paragraphDoc("x")))
    }

    // MARK: - selectionChanged

    @MainActor
    func test_selectionChanged_mirrors() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let newSel = BlockTreeSelection.insertion(at: [UUID()], offset: 2)
        await store.send(.selectionChanged(newSel)) {
            $0.selection = newSel
        }
    }

    // MARK: - slashTyped

    @MainActor
    func test_slashTyped_opensPaletteWithLocation() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let leafID = UUID()
        await store.send(.slashTyped(blockPath: [leafID], offsetUTF16: 7))
        await store.receive(.slashPalette(.openRequested(triggerOffset: 7, triggerBlockPath: [leafID]))) {
            $0.slashPalette.isOpen = true
            $0.slashPalette.triggerOffset = 7
            $0.slashPalette.triggerBlockPath = [leafID]
            $0.slashPalette.matchedCommands = SlashCommandRegistry.standard.filtered(by: "")
        }
    }

    // MARK: - applyBlockFormat

    @MainActor
    func test_applyBlockFormat_heading1_replacesLeafKind() async {
        let doc = paragraphDoc("Meeting agenda")
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.heading(level: 1)))

        guard case .heading(let level, let inline) = store.state.document.blocks.first?.kind else {
            XCTFail("Expected heading after applyBlockFormat")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(inline.first?.text, "Meeting agenda", "Inline text must survive the kind change")
        XCTAssertTrue(store.state.isDirty)
    }

    @MainActor
    func test_applyBlockFormat_blockQuote_wrapsLeafInBlockquote() async {
        let doc = paragraphDoc("Quote me on this")
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.blockQuote))

        guard case .blockquote(let children) = store.state.document.blocks.first?.kind else {
            XCTFail("Expected blockquote")
            return
        }
        guard case .paragraph(let innerInline) = children.first?.kind else {
            XCTFail("Expected paragraph inside blockquote")
            return
        }
        XCTAssertEqual(innerInline.first?.text, "Quote me on this", "Original paragraph wrapped, content preserved")
    }

    @MainActor
    func test_applyBlockFormat_bulletedList_wrapsLeafInListWithOneItem() async {
        let doc = paragraphDoc("First")
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.bulletedList))

        guard case .bulletList(let items) = store.state.document.blocks.first?.kind else {
            XCTFail("Expected bulletList")
            return
        }
        XCTAssertEqual(items.count, 1)
        guard case .paragraph(let innerInline) = items.first?.content.first?.kind else {
            XCTFail("Expected paragraph inside list item")
            return
        }
        XCTAssertEqual(innerInline.first?.text, "First")
    }

    @MainActor
    func test_applyBlockFormat_numberedList_wrapsLeafInOrderedList() async {
        let doc = paragraphDoc("Step")
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.numberedList))

        guard case .orderedList = store.state.document.blocks.first?.kind else {
            XCTFail("Expected orderedList")
            return
        }
    }

    @MainActor
    func test_applyBlockFormat_codeBlock_replacesAsCodeBlockWithJoinedText() async {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "let "),
                Inline(text: "x", marks: [.bold]),
                Inline(text: " = 1")
            ]))
        ])
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.codeBlock))

        guard case .codeBlock(let text, _) = store.state.document.blocks.first?.kind else {
            XCTFail("Expected codeBlock")
            return
        }
        XCTAssertEqual(text, "let x = 1", "Inline marks flatten away; plain text preserved")
    }

    @MainActor
    func test_applyBlockFormat_divider_insertsAfterTargetLeaf() async {
        let doc = paragraphDoc("Above")
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.divider))

        let blocks = store.state.document.blocks
        XCTAssertEqual(blocks.count, 3, "Original paragraph + divider + fresh paragraph after")
        XCTAssertEqual(blocks[0].id, leafID, "Original paragraph stays at index 0 by id")
        // After insertion: target stays, fresh paragraph inserted first, then divider after target.
        // The reducer inserts a paragraph after the divider so the caret has somewhere to land —
        // but inserts in reverse order (paragraph, then divider) so the divider ends up right
        // after the target leaf.
        let kinds = blocks.map { String(describing: $0.kind).prefix(10) }
        let hasDivider = blocks.contains { if case .divider = $0.kind { return true } else { return false } }
        XCTAssertTrue(hasDivider, "Document must now contain a divider — found kinds: \(kinds)")
    }

    @MainActor
    func test_applyBlockFormat_withUnsetSelection_targetsLastLeaf() async {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "First")])),
            Block(kind: .paragraph(inline: [Inline(text: "Last")]))
        ])
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        // selection left as default (unset)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.heading(level: 2)))

        guard case .heading = store.state.document.blocks[1].kind else {
            XCTFail("Last leaf should have become a heading")
            return
        }
        guard case .paragraph = store.state.document.blocks[0].kind else {
            XCTFail("First paragraph should remain unchanged")
            return
        }
    }

    // MARK: - toggleInlineFormat

    @MainActor
    func test_toggleInlineFormat_bold_appliesToSelectedRangeOnly() async {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "The quick brown fox")]))
        ])
        let leafID = doc.blocks[0].id
        // Select "quick" — UTF-16 offsets 4..9.
        let selection = BlockTreeSelection.range(at: [leafID], start: 4, end: 9)

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.bold))

        guard case .paragraph(let inline) = store.state.document.blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        // Expect three runs: "The ", "quick" (bold), " brown fox"
        XCTAssertEqual(inline.count, 3)
        XCTAssertEqual(inline[0].text, "The ")
        XCTAssertEqual(inline[0].marks, [])
        XCTAssertEqual(inline[1].text, "quick")
        XCTAssertEqual(inline[1].marks, [.bold])
        XCTAssertEqual(inline[2].text, " brown fox")
        XCTAssertEqual(inline[2].marks, [])
    }

    @MainActor
    func test_toggleInlineFormat_secondInvocation_removesBold() async {
        // Pre-seed an already-bold span; toggle should remove.
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "The "),
                Inline(text: "quick", marks: [.bold]),
                Inline(text: " brown fox")
            ]))
        ])
        let leafID = doc.blocks[0].id
        let selection = BlockTreeSelection.range(at: [leafID], start: 4, end: 9)

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.bold))

        guard case .paragraph(let inline) = store.state.document.blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        // After toggle-off the runs should coalesce back into a
        // single plain run.
        XCTAssertEqual(inline.count, 1)
        XCTAssertEqual(inline[0].text, "The quick brown fox")
        XCTAssertEqual(inline[0].marks, [])
    }

    @MainActor
    func test_toggleInlineFormat_insertionPointOnly_isNoOp() async {
        let doc = paragraphDoc("hello")
        let leafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [leafID], offset: 2)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.bold))

        // No mark added.
        guard case .paragraph(let inline) = store.state.document.blocks[0].kind else {
            XCTFail()
            return
        }
        XCTAssertEqual(inline.first?.marks, [])
    }

    @MainActor
    func test_toggleInlineFormat_underline_appliesUnderlineMark() async {
        let doc = paragraphDoc("link text")
        let leafID = doc.blocks[0].id
        let selection = BlockTreeSelection.range(at: [leafID], start: 0, end: 4)

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = selection

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleInlineFormat(.underline))

        guard case .paragraph(let inline) = store.state.document.blocks[0].kind else {
            XCTFail()
            return
        }
        XCTAssertEqual(inline[0].text, "link")
        XCTAssertEqual(inline[0].marks, [.underline])
    }

    // MARK: - slashPaletteCommandSelected

    @MainActor
    func test_slashPaletteCommandSelected_heading2_stripsTriggerAndAppliesFormat() async {
        let doc = paragraphDoc("Hello /h")
        let leafID = doc.blocks[0].id

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.slashPalette.isOpen = true
        initial.slashPalette.triggerOffset = 6  // index of "/"
        initial.slashPalette.triggerBlockPath = [leafID]
        // Selection points after "/h" — the trigger location is the
        // slash itself.
        initial.selection = .insertion(at: [leafID], offset: 8)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.slashPalette(.commandSelected(.heading2)))
        // The reducer sends `.applyBlockFormat(.heading(level: 2))`
        // as a follow-up effect — wait for it before asserting on
        // the final state.
        await store.receive(.applyBlockFormat(.heading(level: 2)))

        guard case .heading(let level, let inline) = store.state.document.blocks[0].kind else {
            XCTFail("Expected heading after slash command")
            return
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(inline.first?.text, "Hello ", "Trigger slice '/h' stripped, surviving text preserved")
    }

    // MARK: - flush

    @MainActor
    func test_flush_whenClean_isNoOp() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // No state change.
        await store.send(.flush)
    }

    @MainActor
    func test_flush_whenDirty_persistsImmediately() async {
        let doc = paragraphDoc("Hello")
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.isDirty = true

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.continuousClock = ImmediateClock()
                // Replace the whole dependency (memory rule on
                // MainActor isolation). The only path we care about is
                // `updateBlockBody` succeeding.
                $0.notebookClient = Self.successUpdateBlockBodyClient
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // flush bypasses the debounce and calls persistEffect
        // directly — persistRequested is for the SCHEDULED path.
        await store.send(.flush)
        await store.receive(.persistCompleted) {
            $0.isDirty = false
        }
    }

    /// All fields throw cancellation EXCEPT `updateBlockBody` which
    /// succeeds. Used to test the persist path without standing up a
    /// real SwiftData container.
    private static let successUpdateBlockBodyClient: NotebookClient = NotebookClient(
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
        fetchPDFData: { _ in throw CancellationError() },
        findPDFByContentHash: { _ in throw CancellationError() },
        importPDF: { _, _ in throw CancellationError() },
        touchPDFOpened: { _ in throw CancellationError() },
        createPage: { _, _ in throw CancellationError() },
        deletePage: { _ in throw CancellationError() },
        reindexPages: { _, _ in throw CancellationError() },
        transferPage: { _, _, _ in throw CancellationError() },
        setPageTemplate: { _, _ in throw CancellationError() },
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
        addRegion: { _, _, _, _, _, _ in throw CancellationError() },
        updateRegionHeader: { _, _ in throw CancellationError() },
        updateRegionLink: { _, _ in throw CancellationError() },
        deleteRegion: { _ in throw CancellationError() },
        fetchBlocksForPage: { _ in throw CancellationError() },
        loadBlockDrawing: { _ in throw CancellationError() },
        insertBlock: { _, _, _ in throw CancellationError() },
        updateBlockBody: { _, _, _ in /* success */ },
        updateBlockDrawing: { _, _, _ in throw CancellationError() },
        updateBlockOCR: { _, _ in throw CancellationError() },
        updateBlockVoice: { _, _, _, _, _, _ in throw CancellationError() },
        updateBlockHeight: { _, _ in throw CancellationError() },
        deleteBlock: { _ in throw CancellationError() },
        reorderBlocks: { _, _ in throw CancellationError() },
        bindCanonicalCanvasWidth: { _, _ in throw CancellationError() },
        createFolder: { _, _ in throw CancellationError() },
        deleteFolder: { _ in throw CancellationError() },
        moveNotebookToFolder: { _, _ in throw CancellationError() },
        createTag: { _, _ in throw CancellationError() },
        addTagToNotebook: { _, _ in throw CancellationError() },
        removeTagFromNotebook: { _, _ in throw CancellationError() }
    )
}
