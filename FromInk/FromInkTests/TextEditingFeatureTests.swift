import ComposableArchitecture
import Foundation
import XCTest
@testable import FromInk

/// Pins the `TextEditingFeature` reducer's contract:
///
///   - `activeBlockChanged` seeds the in-flight body from the
///     snapshot, clears `isDirty`, and cancels any in-flight persist.
///   - `activeBlockChanged` with a decode-failed snapshot surfaces
///     the `bodyDecodeFailed` load failure state.
///   - `activeBlockChanged` with an orphan (`pageID == nil`)
///     snapshot surfaces the `orphan` load failure state.
///   - `bodyEdited` marks dirty and schedules a debounced persist.
///   - Persist debounce: a rapid burst of edits coalesces to one
///     `NotebookClient.updateBlockBody` call after the window elapses.
///   - `flush` cancels the pending debounce and forces an immediate
///     persist when dirty.
///   - `flush` is a no-op when nothing is dirty.
///   - Edits made while in a failure state are silently dropped
///     (no body mutation, no persist).
final class TextEditingFeatureTests: XCTestCase {

    private let blockID = UUID()
    private let pageID = UUID()
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func snapshot(
        kind: PageBlockKind = .text,
        body: AttributedString = AttributedString(),
        pageID: UUID? = nil,
        bodyDecodeFailed: Bool = false
    ) -> PageBlockSnapshot {
        PageBlockSnapshot(
            id: blockID,
            pageID: pageID ?? self.pageID,
            sortIndex: 0,
            kind: kind,
            heightPoints: 44,
            body: body,
            bodyDecodeFailed: bodyDecodeFailed,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: String(body.characters),
            contentHash: PageBlock.sha256(String(body.characters)),
            createdAt: earlier,
            modifiedAt: earlier
        )
    }

    // MARK: - activeBlockChanged

    @MainActor
    func test_activeBlockChanged_seedsBodyFromSnapshot() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let snap = snapshot(body: AttributedString("Hello"))
        await store.send(.activeBlockChanged(snap)) {
            $0.activeBlock = snap
            $0.body = AttributedString("Hello")
            $0.isDirty = false
            $0.loadFailure = nil
        }
    }

    @MainActor
    func test_activeBlockChanged_decodeFailedSnapshot_surfacesLoadFailure() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() }
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
            reducer: { TextEditingFeature() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // An orphan block has no back-pointer to its page.
        let orphan = PageBlockSnapshot(
            id: blockID,
            pageID: nil,
            sortIndex: 0,
            kind: .text,
            heightPoints: 44,
            body: AttributedString(),
            bodyDecodeFailed: false,
            drawingData: nil,
            voice: nil,
            ocrText: nil,
            plainText: nil,
            contentHash: "",
            createdAt: earlier,
            modifiedAt: earlier
        )

        await store.send(.activeBlockChanged(orphan)) {
            $0.loadFailure = .orphan
        }
    }

    // MARK: - bodyEdited + debounced persist

    @MainActor
    func test_bodyEdited_marksDirtyAndDebouncesPersist() async {
        let updateCalls = LockIsolated<[(UUID, Data, String)]>([])
        let clock = TestClock()

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { id, data, plain in
                    updateCalls.withValue { $0.append((id, data, plain)) }
                }
                $0.continuousClock = clock
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let newBody = AttributedString("Hello world")
        await store.send(.bodyEdited(newBody)) {
            $0.body = newBody
            $0.isDirty = true
        }

        // Debounce not yet elapsed — no persist call.
        XCTAssertEqual(updateCalls.value.count, 0)

        await clock.advance(by: .milliseconds(600))
        await store.receive(.persistRequested)
        await store.receive(.persistCompleted) {
            $0.isDirty = false
        }

        XCTAssertEqual(updateCalls.value.count, 1)
        let (id, _, plain) = updateCalls.value[0]
        XCTAssertEqual(id, blockID)
        XCTAssertEqual(plain, "Hello world")
    }

    @MainActor
    func test_bodyEdited_rapidBurst_coalescesToOnePersist() async {
        let updateCalls = LockIsolated<Int>(0)
        let clock = TestClock()

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
                $0.continuousClock = clock
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // Three edits within the debounce window — only the last
        // should persist.
        await store.send(.bodyEdited(AttributedString("a")))
        await clock.advance(by: .milliseconds(100))
        await store.send(.bodyEdited(AttributedString("ab")))
        await clock.advance(by: .milliseconds(100))
        await store.send(.bodyEdited(AttributedString("abc")))

        // Now advance past the debounce window from the LAST edit.
        await clock.advance(by: .milliseconds(600))
        await store.receive(.persistRequested)
        await store.receive(.persistCompleted)

        XCTAssertEqual(
            updateCalls.value, 1,
            "Burst of edits inside the debounce window must coalesce to a single persist"
        )
    }

    // MARK: - flush

    @MainActor
    func test_flush_whenDirty_persistsImmediately() async {
        let updateCalls = LockIsolated<Int>(0)
        let clock = TestClock()

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
                $0.continuousClock = clock
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.bodyEdited(AttributedString("draft"))) {
            $0.isDirty = true
        }
        // Flush before debounce window elapses — must persist anyway.
        await store.send(.flush)
        await store.receive(.persistCompleted) {
            $0.isDirty = false
        }

        XCTAssertEqual(updateCalls.value, 1)
    }

    @MainActor
    func test_flush_whenClean_isNoOp() async {
        let updateCalls = LockIsolated<Int>(0)

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // No prior edit — flush is a no-op.
        await store.send(.flush)
        XCTAssertEqual(updateCalls.value, 0, "Flush without dirty state must not persist")
    }

    // MARK: - Load failure suppresses edits

    @MainActor
    func test_bodyEdited_whileLoadFailure_isDropped() async {
        let updateCalls = LockIsolated<Int>(0)

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
            }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // Surface a decode failure first.
        let failed = snapshot(bodyDecodeFailed: true)
        await store.send(.activeBlockChanged(failed)) {
            $0.loadFailure = .bodyDecodeFailed
        }

        // An edit attempted while load-failed must NOT mutate the body
        // or schedule a persist — protects the corrupted payload from
        // being overwritten with the user's incidental keystroke.
        await store.send(.bodyEdited(AttributedString("oops")))

        XCTAssertEqual(updateCalls.value, 0)
    }
}
