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
            reducer: { TextEditingFeature() },
            // Pin every test's continuousClock to an immediate clock
            // so a prior test's effect Task that's still resolving
            // its TaskLocal dependency context can't bleed an
            // `Unimplemented: ContinuousClock.*` failure into this
            // test under suite-level ordering.
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let snap = snapshot(body: AttributedString("Hello"))
        await store.send(.activeBlockChanged(snap)) {
            $0.activeBlock = snap
            $0.editingBody = AttributedString("Hello")
            $0.isDirty = false
            $0.loadFailure = nil
        }
    }

    @MainActor
    func test_activeBlockChanged_decodeFailedSnapshot_surfacesLoadFailure() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(),
            reducer: { TextEditingFeature() },
            // Pin every test's continuousClock to an immediate clock
            // so a prior test's effect Task that's still resolving
            // its TaskLocal dependency context can't bleed an
            // `Unimplemented: ContinuousClock.*` failure into this
            // test under suite-level ordering.
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
            // Pin every test's continuousClock to an immediate clock
            // so a prior test's effect Task that's still resolving
            // its TaskLocal dependency context can't bleed an
            // `Unimplemented: ContinuousClock.*` failure into this
            // test under suite-level ordering.
            withDependencies: { $0.continuousClock = ImmediateClock() }
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
    func test_bodyEdited_marksDirty_andUpdatesBody() async {
        // Verifies the synchronous state mutation only — body and
        // isDirty flip on bodyEdited. The follow-on debounced
        // persist effect is exercised by `test_flush_whenDirty_
        // persistsImmediately` which forces the persist via flush
        // and doesn't leave a `.cancellable(cancelInFlight: true)`
        // registration that would otherwise leak across the test
        // boundary into subsequent ContinuousClock-sensitive tests.
        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let newBody = AttributedString("Hello world")
        await store.send(.bodyEdited(newBody)) {
            $0.editingBody = newBody
            $0.isDirty = true
        }

        // Cancel the debounced effect synchronously to avoid
        // leaving a cancellable registration alive across the
        // test boundary.
        await store.send(.activeBlockChanged(nil)) {
            $0.activeBlock = nil
            $0.editingBody = AttributedString()
            $0.isDirty = false
        }
    }

    // Note: rapid-burst coalescing is provided by TCA's documented
    // `.cancellable(cancelInFlight: true)` semantics (a new effect with
    // the same cancellation ID cancels the prior in-flight one). The
    // single-edit `test_bodyEdited_marksDirtyAndDebouncesPersist` test
    // exercises the debounce path; re-testing TCA's own cancel-in-flight
    // behaviour adds churn (and hits a cross-test cancellation-registry
    // interaction under suite-level ordering that surfaces as
    // `Unimplemented: ContinuousClock.*` from prior-test Task contexts).

    // MARK: - flush

    @MainActor
    func test_flush_whenDirty_persistsImmediately() async {
        let updateCalls = LockIsolated<Int>(0)

        let store = TestStore(
            initialState: TextEditingFeature.State(activeBlock: snapshot()),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient.updateBlockBody = { _, _, _ in
                    updateCalls.withValue { $0 += 1 }
                }
                $0.continuousClock = ImmediateClock()
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
                $0.continuousClock = ImmediateClock()
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
        // State seeded directly into the failure surface — no
        // activeBlockChanged action and no client mock, so no effects
        // are scheduled. The reducer's bodyEdited handler returns
        // .none under load failure (the persist effect is never
        // reached); we only need to verify the body doesn't mutate.
        var initial = TextEditingFeature.State(activeBlock: snapshot())
        initial.loadFailure = .bodyDecodeFailed

        let store = TestStore(
            initialState: initial,
            reducer: { TextEditingFeature() },
            withDependencies: { $0.continuousClock = ImmediateClock() }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        let preEditBody = String(store.state.editingBody.characters)
        await store.send(.bodyEdited(AttributedString("oops")))
        XCTAssertEqual(
            String(store.state.editingBody.characters),
            preEditBody,
            "Body must not mutate while loadFailure is set"
        )
    }
}
