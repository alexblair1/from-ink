import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "NotePage")

/// Owns ONE page's block content — the reducer the hybrid block stack
/// hangs off (hybrid_page_edd.md §5.1).
///
/// **Phase 1 scope (text-only).** The page hosts exactly one text
/// block; this feature owns its load, the empty-page auto-seed (the
/// A5 in-flight guard, lifted from `NotebookFeature`), and the single
/// live `TextEditingFeature` child. The block ARRAY (`BlockRow`s for
/// interleaved text/ink) arrives with Phase 2/3 — the state shape here
/// is deliberately minimal so the Phase 1 cutover is a pure ownership
/// move for the existing textNote behaviour.
///
/// **Lifecycle.** `NotebookFeature` creates this state when the
/// notebook resolves as `.textNote` and pages are available, keeps it
/// ALIVE across page swipes (so the outgoing block's flush effect
/// reads un-reset editor state — the same serialization the old
/// `currentIndexChanged` concatenate relied on), and drives swipes via
/// `.pageChanged(newPageID)`.
struct NotePageFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        /// The page whose blocks this feature currently owns. Mutated
        /// only by `.pageChanged` (page swipe).
        var pageID: UUID

        /// True while a text-block seed insert is in flight (readiness
        /// audit A5, moved here from `NotebookFeature`). `blocksLoaded`
        /// can fire multiple times before the first seed lands — a
        /// store-change refresh racing the insert — and each empty
        /// result would otherwise dispatch ANOTHER `insertBlock`.
        var isSeedingBlock: Bool = false

        /// The ONE live text editor (hybrid_page_edd.md §3.2 —
        /// active-block-swap model; a single instance regardless of
        /// how many text blocks a page eventually hosts).
        var textEditing: TextEditingFeature.State = .init()

        init(pageID: UUID) {
            self.pageID = pageID
        }
    }

    @CasePathable
    enum Action: Equatable {
        /// Fetch the page's blocks. Sent by the parent on creation and
        /// on store-change refreshes; internally on `pageChanged`.
        case loadBlocks

        /// The page changed under this feature (swipe). Flushes the
        /// outgoing block's pending edits BEFORE loading the new
        /// page's blocks — `.concatenate` runs the flush effect to
        /// completion first, so the prior block's in-flight write
        /// can't race the new block's snapshot landing under the
        /// editor (same contract the pre-Phase-1 `NotebookFeature`
        /// swipe path had).
        case pageChanged(UUID)

        case blocksLoaded([PageBlockSnapshot])

        /// Result of the empty-page auto-seed. `nil` means the insert
        /// failed (already logged); either way the in-flight flag
        /// clears so the empty-state tap can retry (audit A5).
        case blockSeeded(PageBlockSnapshot?)

        /// User-initiated re-fetch — the empty-state tap and the
        /// decode-failure retry in `TextBlockView`.
        case reloadRequested

        case textEditing(TextEditingFeature.Action)
    }

    @Dependency(\.notebookClient) var notebookClient

    var body: some Reducer<State, Action> {
        Scope(state: \.textEditing, action: \.textEditing) {
            TextEditingFeature()
        }

        Reduce { state, action in
            switch action {
            case .loadBlocks, .reloadRequested:
                return loadBlocksEffect(pageID: state.pageID)

            case .pageChanged(let newPageID) where newPageID == state.pageID:
                // Same page (index churn without a page change) —
                // nothing to flush or reload.
                return .none

            case .pageChanged(let newPageID):
                state.pageID = newPageID
                state.isSeedingBlock = false
                return .concatenate(
                    .send(.textEditing(.flush)),
                    loadBlocksEffect(pageID: newPageID)
                )

            case .blocksLoaded(let blocks):
                // Phase 1: each page hosts exactly one text block. If
                // none exists yet, seed one so the editor opens
                // cleanly. Otherwise route the first text block to the
                // editor feature.
                let firstTextBlock = blocks
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .first(where: { $0.kind == .text })
                if let snap = firstTextBlock {
                    state.isSeedingBlock = false
                    return .send(.textEditing(.activeBlockChanged(snap)))
                }
                // In-flight guard (readiness audit A5): a second empty
                // load racing the first seed must not insert a
                // duplicate block.
                guard !state.isSeedingBlock else { return .none }
                state.isSeedingBlock = true
                let pageID = state.pageID
                return .run { send in
                    do {
                        let snap = try await notebookClient.insertBlock(pageID, .text, nil)
                        await send(.blockSeeded(snap))
                    } catch {
                        log.error("Seed text block failed: \(error.localizedDescription)")
                        await send(.blockSeeded(nil))
                    }
                }

            case .blockSeeded(let snap):
                state.isSeedingBlock = false
                // Route only when the seed still targets the page this
                // feature is showing — a swipe mid-seed must not hand
                // the editor a block from the page the user left.
                guard let snap, snap.pageID == state.pageID else { return .none }
                return .send(.textEditing(.activeBlockChanged(snap)))

            case .textEditing:
                return .none
            }
        }
    }

    // MARK: - Effects

    private func loadBlocksEffect(pageID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let blocks = try await notebookClient.fetchBlocksForPage(pageID)
                await send(.blocksLoaded(blocks))
            } catch {
                log.error("loadBlocks failed for page \(pageID): \(error.localizedDescription)")
            }
        }
        .cancellable(id: "notePageBlocksLoad", cancelInFlight: true)
    }
}
