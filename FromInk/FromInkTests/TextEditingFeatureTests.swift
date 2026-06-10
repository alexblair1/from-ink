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
        // Regression for fix C1: the previous implementation inserted
        // [target, paragraph, divider] (wrong order). Correct order is
        // [target, divider, fresh paragraph for the caret].
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
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].id, leafID, "Original paragraph stays at index 0")
        // Pin the EXACT order — block at index 1 is the divider, not
        // the fresh paragraph.
        if case .divider = blocks[1].kind {
            // ok
        } else {
            XCTFail("Expected divider at index 1, got \(blocks[1].kind)")
        }
        // Block at index 2 is the fresh paragraph for the caret.
        guard case .paragraph(let freshInline) = blocks[2].kind else {
            XCTFail("Expected fresh paragraph at index 2")
            return
        }
        XCTAssertEqual(freshInline, [], "Fresh paragraph below the divider must be empty")
        // Caret lands on the fresh paragraph below the rule.
        XCTAssertEqual(store.state.selection.path, [blocks[2].id])
        XCTAssertEqual(store.state.selection.startUTF16, 0)
    }

    // MARK: - C2 — leaf identity preservation on wrap

    @MainActor
    func test_applyBlockFormat_blockQuote_preservesInnerLeafID() async {
        // Regression for fix C2: wrapping a leaf in a blockquote must
        // KEEP the leaf's id on the inner paragraph so NoteRegion text
        // anchors continue to point at the same structural unit (the
        // leaf carrying the user's content).
        let doc = paragraphDoc("Important text")
        let originalLeafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [originalLeafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.blockQuote))

        guard case .blockquote(let children) = store.state.document.blocks[0].kind else {
            XCTFail("Expected blockquote")
            return
        }
        XCTAssertEqual(
            children.first?.id, originalLeafID,
            "Inner leaf MUST keep the original id so anchor paths can be rewritten to it"
        )
        // The outer wrapper has a different id.
        XCTAssertNotEqual(
            store.state.document.blocks[0].id, originalLeafID,
            "Outer wrapper has a fresh id"
        )
        // Selection updated to address the leaf at its new path.
        XCTAssertEqual(
            store.state.selection.path,
            [store.state.document.blocks[0].id, originalLeafID],
            "Selection path must prefix with the new outer container id"
        )
    }

    @MainActor
    func test_applyBlockFormat_bulletedList_preservesInnerLeafID() async {
        let doc = paragraphDoc("Item text")
        let originalLeafID = doc.blocks[0].id
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [originalLeafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.bulletedList))

        guard case .bulletList(let items) = store.state.document.blocks[0].kind else {
            XCTFail("Expected bulletList")
            return
        }
        XCTAssertEqual(
            items.first?.content.first?.id, originalLeafID,
            "Inner paragraph of the list item MUST keep the original leaf id"
        )
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

    // MARK: - C3 — stripTriggerSlice preserves marks

    @MainActor
    func test_slashPaletteCommandSelected_preservesMarksOnSurvivingPrefix() async {
        // Regression for fix C3: when the user has bolded text BEFORE
        // typing "/", the bold MUST survive the strip. The previous
        // implementation rebuilt the paragraph as a single unmarked
        // inline run, silently destroying the user's formatting.
        let bold = Inline(text: "Bold", marks: [.bold])
        let plain = Inline(text: " plain /h", marks: [])
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [bold, plain]))
        ])
        let leafID = doc.blocks[0].id

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        // "Bold plain /h" — UTF-16 offsets: 0=B, 4=' ', 10='/', 11='h'.
        initial.slashPalette.isOpen = true
        initial.slashPalette.triggerOffset = 11   // index of "/"
        initial.slashPalette.triggerBlockPath = [leafID]
        initial.selection = .insertion(at: [leafID], offset: 13)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.slashPalette(.commandSelected(.heading2)))
        await store.receive(.applyBlockFormat(.heading(level: 2)))

        // Heading 2 applied. Inline runs reflect the surviving text
        // up to the trigger, with bold preserved on the "Bold" prefix.
        guard case .heading(_, let inline) = store.state.document.blocks[0].kind else {
            XCTFail("Expected heading")
            return
        }
        XCTAssertEqual(inline.count, 2, "Both runs (bold prefix + plain space portion) preserved")
        XCTAssertEqual(inline[0].text, "Bold")
        XCTAssertEqual(inline[0].marks, [.bold], "Bold mark MUST survive the strip")
        XCTAssertEqual(inline[1].text, " plain ", "Plain text up to the trigger preserved")
        XCTAssertEqual(inline[1].marks, [], "Plain text run keeps its (empty) mark set")
    }

    // MARK: - S1 — selection reset after stripTriggerSlice

    @MainActor
    func test_slashPaletteCommandSelected_resetsSelectionToTriggerOffset() async {
        let doc = paragraphDoc("Hello /heading")
        let leafID = doc.blocks[0].id

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.slashPalette.isOpen = true
        initial.slashPalette.triggerOffset = 6
        initial.slashPalette.triggerBlockPath = [leafID]
        // Caret was past the filter text at offset 14 (end of "/heading").
        initial.selection = .insertion(at: [leafID], offset: 14)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.slashPalette(.commandSelected(.heading1)))
        await store.receive(.applyBlockFormat(.heading(level: 1)))

        // Selection's UTF-16 offset must reset to the trigger
        // position (end of surviving text). Without this, the offset
        // would point past the leaf's new end after the strip.
        XCTAssertEqual(store.state.selection.path, [leafID])
        XCTAssertEqual(store.state.selection.startUTF16, 6)
        XCTAssertEqual(store.state.selection.endUTF16, 6)
    }

    // MARK: - Nested container traversal (fix C4)

    @MainActor
    func test_applyBlockFormat_inDeeplyNestedBlockquote_targetsCorrectLeaf() async {
        // Regression for fix C4: mapDescendant / replaceDescendant must
        // recurse through container children even when the path's
        // first id isn't a direct child. Construct
        // blockquote(blockquote(paragraph)) and apply heading to the
        // inner paragraph via its FULL path.
        let inner = Block(kind: .paragraph(inline: [Inline(text: "Nested")]))
        let middle = Block(kind: .blockquote(children: [inner]))
        let outer = Block(kind: .blockquote(children: [middle]))
        let doc = RichTextDocument(blocks: [outer])

        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        // Full path: outer → middle → inner.
        initial.selection = .insertion(at: [outer.id, middle.id, inner.id], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.applyBlockFormat(.heading(level: 3)))

        // The inner paragraph should now be a heading. Reach into the
        // nested structure to verify.
        guard case .blockquote(let outerChildren) = store.state.document.blocks[0].kind,
              case .blockquote(let middleChildren) = outerChildren[0].kind,
              case .heading(let level, let text) = middleChildren[0].kind else {
            XCTFail("Inner paragraph should have become a heading")
            return
        }
        XCTAssertEqual(level, 3)
        XCTAssertEqual(text.first?.text, "Nested")
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

    // MARK: - exitList

    /// Only-item case: the list dissolves and is replaced by the
    /// exited paragraph. Paragraph preserves the item's leaf id so
    /// the caller's selection stays valid without a re-bridge.
    @MainActor
    func test_exitList_singleItemList_dissolvesIntoParagraph() async {
        let leafID = UUID()
        let listID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [
                    Block(id: leafID, kind: .paragraph(inline: []))
                ])
            ]))
        ])
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [listID, leafID], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.exitList)

        XCTAssertEqual(store.state.document.blocks.count, 1)
        guard case .paragraph(let inline) = store.state.document.blocks.first?.kind else {
            XCTFail("Expected list to dissolve into a paragraph")
            return
        }
        XCTAssertTrue(inline.isEmpty, "Exited paragraph starts empty")
        XCTAssertEqual(store.state.document.blocks.first?.id, leafID,
                       "Paragraph reuses the empty item's id for selection stability")
        XCTAssertEqual(store.state.selection.path, [leafID])
        XCTAssertEqual(store.state.selection.startUTF16, 0)
    }

    /// Trailing-empty-item case: paragraph emits AFTER the
    /// surviving list, list container's id is preserved.
    @MainActor
    func test_exitList_lastItemEmpty_emitsParagraphAfterList() async {
        let listID = UUID()
        let firstItemLeaf = UUID()
        let secondItemLeaf = UUID()
        let emptyLeaf = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: firstItemLeaf, kind: .paragraph(inline: [Inline(text: "one")]))]),
                ListItem(id: UUID(), content: [Block(id: secondItemLeaf, kind: .paragraph(inline: [Inline(text: "two")]))]),
                ListItem(id: UUID(), content: [Block(id: emptyLeaf, kind: .paragraph(inline: []))])
            ]))
        ])
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [listID, emptyLeaf], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.exitList)

        XCTAssertEqual(store.state.document.blocks.count, 2)
        XCTAssertEqual(store.state.document.blocks[0].id, listID,
                       "Surviving list keeps the outer container id")
        guard case .bulletList(let items) = store.state.document.blocks[0].kind else {
            XCTFail("Expected surviving bulletList")
            return
        }
        XCTAssertEqual(items.count, 2, "Empty item removed; first two items remain")
        XCTAssertEqual(items[0].content.first?.id, firstItemLeaf)
        XCTAssertEqual(items[1].content.first?.id, secondItemLeaf)

        guard case .paragraph = store.state.document.blocks[1].kind else {
            XCTFail("Expected paragraph after list")
            return
        }
        XCTAssertEqual(store.state.document.blocks[1].id, emptyLeaf)
        XCTAssertEqual(store.state.selection.path, [emptyLeaf])
    }

    /// Leading-empty-item case: paragraph emits BEFORE the
    /// surviving list.
    @MainActor
    func test_exitList_firstItemEmpty_emitsParagraphBeforeList() async {
        let listID = UUID()
        let emptyLeaf = UUID()
        let secondLeaf = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: emptyLeaf, kind: .paragraph(inline: []))]),
                ListItem(id: UUID(), content: [Block(id: secondLeaf, kind: .paragraph(inline: [Inline(text: "second")]))])
            ]))
        ])
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [listID, emptyLeaf], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.exitList)

        XCTAssertEqual(store.state.document.blocks.count, 2)
        guard case .paragraph = store.state.document.blocks[0].kind else {
            XCTFail("Expected paragraph before surviving list")
            return
        }
        XCTAssertEqual(store.state.document.blocks[0].id, emptyLeaf)
        guard case .bulletList(let items) = store.state.document.blocks[1].kind else {
            XCTFail("Expected surviving bulletList")
            return
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content.first?.id, secondLeaf)
    }

    /// Middle-empty-item case: the list SPLITS into a prefix list,
    /// paragraph, and suffix list. The prefix list keeps the
    /// original container id; the suffix list gets a fresh id
    /// (anchor migration is a follow-up).
    @MainActor
    func test_exitList_middleItemEmpty_splitsListAroundParagraph() async {
        let listID = UUID()
        let firstLeaf = UUID()
        let emptyLeaf = UUID()
        let thirdLeaf = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(id: UUID(), content: [Block(id: firstLeaf, kind: .paragraph(inline: [Inline(text: "a")]))]),
                ListItem(id: UUID(), content: [Block(id: emptyLeaf, kind: .paragraph(inline: []))]),
                ListItem(id: UUID(), content: [Block(id: thirdLeaf, kind: .paragraph(inline: [Inline(text: "c")]))])
            ]))
        ])
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [listID, emptyLeaf], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.exitList)

        XCTAssertEqual(store.state.document.blocks.count, 3)
        XCTAssertEqual(store.state.document.blocks[0].id, listID, "Prefix list keeps the original outer id")
        guard case .bulletList(let prefixItems) = store.state.document.blocks[0].kind else {
            XCTFail("Expected prefix bulletList")
            return
        }
        XCTAssertEqual(prefixItems.count, 1)
        XCTAssertEqual(prefixItems[0].content.first?.id, firstLeaf)

        XCTAssertEqual(store.state.document.blocks[1].id, emptyLeaf)
        guard case .paragraph = store.state.document.blocks[1].kind else {
            XCTFail("Expected paragraph between split lists")
            return
        }

        XCTAssertNotEqual(store.state.document.blocks[2].id, listID,
                          "Suffix list gets a fresh outer id")
        guard case .bulletList(let suffixItems) = store.state.document.blocks[2].kind else {
            XCTFail("Expected suffix bulletList")
            return
        }
        XCTAssertEqual(suffixItems.count, 1)
        XCTAssertEqual(suffixItems[0].content.first?.id, thirdLeaf)
    }

    /// Ordered list parity: empty item in an orderedList exits to
    /// a paragraph with the same surgery (numbering rebuilds on
    /// the surviving list).
    @MainActor
    func test_exitList_orderedList_lastItemEmpty_emitsParagraphAfter() async {
        let listID = UUID()
        let firstLeaf = UUID()
        let emptyLeaf = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .orderedList(items: [
                ListItem(id: UUID(), content: [Block(id: firstLeaf, kind: .paragraph(inline: [Inline(text: "one")]))]),
                ListItem(id: UUID(), content: [Block(id: emptyLeaf, kind: .paragraph(inline: []))])
            ]))
        ])
        var initial = TextEditingFeature.State(activeBlock: snapshot(document: doc))
        initial.document = doc
        initial.selection = .insertion(at: [listID, emptyLeaf], offset: 0)

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.exitList)

        XCTAssertEqual(store.state.document.blocks.count, 2)
        guard case .orderedList(let items) = store.state.document.blocks[0].kind else {
            XCTFail("Expected surviving orderedList")
            return
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content.first?.id, firstLeaf)
        XCTAssertEqual(store.state.document.blocks[1].id, emptyLeaf)
    }

    /// Selection not pointing at a list-item leaf — exitList is a
    /// no-op. Defends against the editor firing the command
    /// spuriously (e.g. a future code path that gets the
    /// detection wrong).
    @MainActor
    func test_exitList_notInsideList_isNoOp() async {
        let doc = paragraphDoc("Hello")
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

        // No state change — exitList early-returns when the
        // selection's container isn't a list.
        await store.send(.exitList)
        XCTAssertEqual(store.state.document, doc, "Document unchanged")
        XCTAssertFalse(store.state.isDirty)
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
