import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "TextEditingFeature")

/// Owns the state and effects for editing a single text block.
///
/// **Scope.** This feature edits ONE block at a time — the active text
/// block on the current page. Multi-block composition (hybrid pages
/// where multiple text/ink/voice blocks coexist) is handled at the
/// `NotePageFeature` level which scopes a `TextEditingFeature` per
/// active text block.
///
/// **Persistence.** Every body change debounces a `NotebookClient.
/// updateBlockBody` write. Debounce window is 600ms — fast enough that
/// a navigate-away within the debounce window flushes via the
/// reducer's `.flush` action; slow enough that rapid typing doesn't
/// thrash SwiftData / CKAsset on every keystroke.
///
/// **Encoding.** Body archival routes through `PageBlockSnapshot.
/// encodeBody(_:)` so the encoding path (Path B with `FromInkAttributes`
/// scope) lives in one place. The reducer is encoder-agnostic.
///
/// **Equality cost.** `AttributedString.Equatable` is O(n). Typical
/// block sizes are <10 KB so per-action diff cost is negligible. The
/// 50 KB threshold from EDD §5.3 hasn't tripped — when it does, the
/// fix is a hash-wrapped equality helper, not an architectural change.
struct TextEditingFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        /// The block being edited. nil when no text block is active
        /// (e.g. page just loaded, no blocks yet).
        var activeBlock: PageBlockSnapshot? = nil

        /// In-memory body for the active edit session. Mirrors
        /// `activeBlock?.body` initially and tracks every keystroke;
        /// the debounced effect flushes it back through the client.
        var body: AttributedString = AttributedString()

        /// Set when the body has unsaved changes since the last
        /// successful persist. Surfaces a "saving…" affordance and
        /// gates the navigate-away flush path.
        var isDirty: Bool = false

        /// Surface for the load-failure state (decode error,
        /// orphan block). Renders the bodyDecodeFailed placeholder
        /// in `TextBlockView` rather than an empty editor.
        var loadFailure: LoadFailure? = nil

        enum LoadFailure: Equatable, Sendable {
            case bodyDecodeFailed
            case orphan
        }
    }

    @CasePathable
    enum Action: Equatable {
        /// Wire a freshly loaded snapshot into the editor. Replaces
        /// any prior in-flight edit session; the caller is expected
        /// to flush first if `isDirty` is true.
        case activeBlockChanged(PageBlockSnapshot?)

        /// User typed; in-memory body update.
        case bodyEdited(AttributedString)

        /// Debounced commit triggered by `.bodyEdited` after the
        /// debounce window. Encodes via `PageBlockSnapshot.encodeBody`
        /// and writes through `NotebookClient.updateBlockBody`.
        case persistRequested

        /// Encode + persist succeeded. Clears `isDirty`.
        case persistCompleted

        /// Encode or persist failed. Logged via OSLog; `isDirty`
        /// stays true so a future commit retries.
        case persistFailed(reason: String)

        /// Synchronous flush requested by the wiring view (navigate-
        /// away, scene background). Cancels any in-flight debounce
        /// and persists immediately if dirty.
        case flush
    }

    @Dependency(\.notebookClient) var notebookClient
    @Dependency(\.continuousClock) var clock

    private static let persistCancelID = "TextEditingFeature.persist"
    private static let debounceMilliseconds: Int = 600

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .activeBlockChanged(let snapshot):
                // Resolve load-failure surfaces up front so the view
                // can render the right placeholder before any edit.
                if let snapshot {
                    if snapshot.pageID == nil {
                        state.loadFailure = .orphan
                    } else if snapshot.bodyDecodeFailed {
                        state.loadFailure = .bodyDecodeFailed
                    } else {
                        state.loadFailure = nil
                    }
                } else {
                    state.loadFailure = nil
                }
                state.activeBlock = snapshot
                state.body = snapshot?.body ?? AttributedString()
                state.isDirty = false
                return .cancel(id: Self.persistCancelID)

            case .bodyEdited(let new):
                guard state.loadFailure == nil else { return .none }
                state.body = new
                state.isDirty = true
                return .run { send in
                    try await clock.sleep(for: .milliseconds(Self.debounceMilliseconds))
                    await send(.persistRequested)
                }
                .cancellable(id: Self.persistCancelID, cancelInFlight: true)

            case .persistRequested:
                return persistEffect(state: state)

            case .persistCompleted:
                state.isDirty = false
                return .none

            case .persistFailed(let reason):
                log.error("Body persist failed: \(reason, privacy: .public)")
                return .none

            case .flush:
                guard state.isDirty, state.loadFailure == nil else {
                    return .cancel(id: Self.persistCancelID)
                }
                return .merge(
                    .cancel(id: Self.persistCancelID),
                    persistEffect(state: state)
                )
            }
        }
    }

    private func persistEffect(state: State) -> Effect<Action> {
        guard let blockID = state.activeBlock?.id else { return .none }
        let body = state.body
        return .run { send in
            do {
                let data = try PageBlockSnapshot.encodeBody(body)
                let plain = String(body.characters)
                try await notebookClient.updateBlockBody(blockID, data, plain)
                await send(.persistCompleted)
            } catch {
                await send(.persistFailed(reason: error.localizedDescription))
            }
        }
    }
}
