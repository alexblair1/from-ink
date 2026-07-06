import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Notebook")

/// Owns the page list for a single open notebook. Fetches `NotePageSnapshot`s
/// via `NotebookClient` on appear, observes `NSManagedObjectContextDidSave`
/// to refresh when pages are added/removed/transferred from elsewhere.
///
/// **Composition:** presented by `HomeFeature` via `@Presents var notebook`.
/// When the parent's `.notebookTapped` fires, it constructs this state with
/// `notebookID` and `notebookTitle` from the tapped library snapshot.
///
/// **First-page seeding:** when the first load returns no pages (a freshly
/// created notebook), the reducer auto-creates a blank page so the
/// canvas is never empty.
struct NotebookFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        let notebookID: UUID
        var notebookTitle: String
        /// The notebook's variant — `.notebook` / `.quickSheet` route
        /// to the ink CanvasScreen; `.textNote` routes to the text
        /// editor wiring (see `TextNoteWiringView`).
        ///
        /// `nil` is the "not yet resolved" state. `NotebookScreen`
        /// renders a loading placeholder until refresh fires
        /// `notebookTypeResolved` — without this, opening a textNote
        /// notebook would flash the canvas screen briefly before
        /// swapping in the text editor.
        var notebookType: NotebookType? = nil
        var pages: [NotePageSnapshot] = []
        var currentIndex: Int = 0
        var hasLoadedOnce: Bool = false

        /// True while a text-block seed insert is in flight (readiness
        /// audit A5). `textBlocksLoaded` can fire multiple times before
        /// the first seed lands — double `onAppear`, a store-change
        /// refresh racing the insert — and each empty result would
        /// otherwise dispatch ANOTHER `insertBlock`, leaving duplicate
        /// text blocks on the page. Cleared when the seed lands
        /// (`textBlockSeeded`) or a loaded block makes seeding moot.
        var isSeedingTextBlock: Bool = false

        /// Toolbar lives at the notebook level (not per-page) so tool
        /// selection persists across page swipes and `ToolbarWiringView`
        /// renders once as a sibling of the `TabView`.
        var toolbar: ToolbarFeature.State = .init()

        /// Active text-block editor scoped under this notebook. Only
        /// meaningful when `notebookType == .textNote`; the canvas
        /// path ignores it.
        var textEditing: TextEditingFeature.State = .init()

        /// Template of the page the user is currently viewing. Derived
        /// from the page snapshot so it always reflects what's actually
        /// stored — no separate notebook-wide field to drift out of
        /// sync. Defaults to `.none` when the page list is empty
        /// (e.g. mid-seed of the first page).
        var currentTemplate: CanvasTemplate {
            guard currentIndex >= 0, currentIndex < pages.count else { return .none }
            return pages[currentIndex].template
        }

        init(notebookID: UUID, notebookTitle: String) {
            self.notebookID = notebookID
            self.notebookTitle = notebookTitle
        }
    }

    @CasePathable
    enum Action: Equatable {
        case onAppear
        case storeDidChange
        case pagesLoaded([NotePageSnapshot])
        /// Notebook variant resolved during refresh. Routes
        /// `NotebookScreen` to either the canvas (ink) or text-editor
        /// (textNote) wiring on the next render.
        case notebookTypeResolved(NotebookType)
        /// Blocks loaded for the current text-note page. Forwarded to
        /// `TextEditingFeature` as the active block snapshot. Ink
        /// notebooks ignore this entirely.
        case textBlocksLoaded([PageBlockSnapshot])
        /// User-initiated re-fetch of the active text-note page's
        /// blocks. Wired to the empty-state tap and decode-failure
        /// retry in `TextBlockView` so a failed auto-seed or a
        /// corrupted body can be recovered without closing the note.
        case textBlocksReloadRequested
        /// Result of the auto-seed insert for an empty text-note page.
        /// `nil` means the insert failed (already logged); either way
        /// the in-flight flag clears so a retry can re-arm seeding.
        case textBlockSeeded(PageBlockSnapshot?)
        case addPageTapped
        case pageCreated(NotePageSnapshot)
        case currentIndexChanged(Int)
        /// User picked a template in the picker panel. Reducer
        /// persists it to the **current page** via `setPageTemplate`
        /// and dispatches `.pageTemplateUpdated` with the refreshed
        /// snapshot.
        case templateSelected(CanvasTemplate)
        /// Refreshed snapshot landed from `setPageTemplate`. Reducer
        /// swaps it into `state.pages` by id so the canvas reads the
        /// new template without round-tripping through the store-
        /// change observer.
        case pageTemplateUpdated(NotePageSnapshot)
        case toolbar(ToolbarFeature.Action)
        case textEditing(TextEditingFeature.Action)
    }

    @Dependency(\.notebookClient) var notebookClient

    var body: some Reducer<State, Action> {
        Scope(state: \.toolbar, action: \.toolbar) {
            ToolbarFeature()
        }
        Scope(state: \.textEditing, action: \.textEditing) {
            TextEditingFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    refresh(notebookID: state.notebookID),
                    observeStoreChanges(),
                    .send(.toolbar(.onAppear))
                )

            case .storeDidChange:
                return refresh(notebookID: state.notebookID)

            case .pagesLoaded(let pages):
                let wasFirstLoad = !state.hasLoadedOnce
                state.pages = pages
                state.hasLoadedOnce = true
                // Clamp the current index if pages shrank out from under us.
                if state.currentIndex >= pages.count {
                    state.currentIndex = max(0, pages.count - 1)
                }
                if wasFirstLoad && pages.isEmpty {
                    return seedFirstPage(notebookID: state.notebookID)
                }
                // textNote variant: reload the active page's blocks
                // whenever the page list changes.
                if state.notebookType == .textNote,
                   let pageID = state.pages[safe: state.currentIndex]?.id {
                    return loadTextBlocks(pageID: pageID)
                }
                return .none

            case .notebookTypeResolved(let type):
                state.notebookType = type
                // Ink variants don't drive textEditing — early-out.
                guard type == .textNote,
                      let pageID = state.pages[safe: state.currentIndex]?.id
                else { return .none }
                return loadTextBlocks(pageID: pageID)

            case .textBlocksReloadRequested:
                guard state.notebookType == .textNote,
                      let pageID = state.pages[safe: state.currentIndex]?.id
                else { return .none }
                return loadTextBlocks(pageID: pageID)

            case .textBlocksLoaded(let blocks):
                // For v1 textNote, each page hosts exactly one text
                // block. If none exists yet, seed one so the editor
                // opens cleanly. Otherwise route the first text block
                // to the editor feature.
                let firstTextBlock = blocks
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .first(where: { $0.kind == .text })
                if let snap = firstTextBlock {
                    state.isSeedingTextBlock = false
                    return .send(.textEditing(.activeBlockChanged(snap)))
                }
                // In-flight guard (readiness audit A5): a second empty
                // load racing the first seed must not insert a
                // duplicate block.
                guard !state.isSeedingTextBlock,
                      let pageID = state.pages[safe: state.currentIndex]?.id
                else { return .none }
                state.isSeedingTextBlock = true
                return .run { send in
                    do {
                        let snap = try await notebookClient.insertBlock(pageID, .text, nil)
                        await send(.textBlockSeeded(snap))
                    } catch {
                        log.error("Seed text block failed: \(error.localizedDescription)")
                        await send(.textBlockSeeded(nil))
                    }
                }

            case .textBlockSeeded(let snap):
                state.isSeedingTextBlock = false
                // Route only when the seed still targets the page the
                // user is looking at — a swipe mid-seed must not hand
                // the editor a block from the page they left.
                guard let snap,
                      state.pages[safe: state.currentIndex]?.id == snap.pageID
                else { return .none }
                return .send(.textEditing(.activeBlockChanged(snap)))

            case .addPageTapped:
                // New pages inherit the **current page's** template so
                // the user's recent choice flows forward. If the user
                // had switched templates on the page they're viewing
                // and then taps +, the new page picks up that switch.
                let id = state.notebookID
                let inherited = state.currentTemplate.rawValue
                return .run { send in
                    do {
                        let snap = try await notebookClient.createPage(id, inherited)
                        await send(.pageCreated(snap))
                    } catch {
                        log.error("addPageTapped: createPage failed — \(error.localizedDescription)")
                    }
                }

            case .pageCreated(let snap):
                // Optimistic insert + jump-to-page. The store-change
                // observation will refresh the list shortly; we pre-seed
                // so the TabView animates to the new page without waiting
                // for the notification round-trip.
                if !state.pages.contains(where: { $0.id == snap.id }) {
                    state.pages.append(snap)
                }
                if let idx = state.pages.firstIndex(where: { $0.id == snap.id }) {
                    state.currentIndex = idx
                }
                return .none

            case .currentIndexChanged(let idx):
                state.currentIndex = idx
                // textNote variants reload the active page's blocks
                // when the user swipes pages so the editor binds to
                // the right block.
                if state.notebookType == .textNote,
                   let pageID = state.pages[safe: idx]?.id {
                    // `.concatenate` runs the flush effect to
                    // completion before kicking off the load, so the
                    // prior block's in-flight write can't race the
                    // new block's snapshot landing under the editor.
                    return .concatenate(
                        .send(.textEditing(.flush)),
                        loadTextBlocks(pageID: pageID)
                    )
                }
                return .none

            case .templateSelected(let template):
                state.toolbar.openPanel = nil
                guard let pageID = state.pages[safe: state.currentIndex]?.id else {
                    // No current page (mid-seed); nothing to persist.
                    return .none
                }
                let raw = template.rawValue
                return .run { send in
                    do {
                        let snap = try await notebookClient.setPageTemplate(pageID, raw)
                        await send(.pageTemplateUpdated(snap))
                    } catch {
                        log.error("setPageTemplate failed for page \(pageID): \(error.localizedDescription)")
                    }
                }

            case .pageTemplateUpdated(let snap):
                if let idx = state.pages.firstIndex(where: { $0.id == snap.id }) {
                    state.pages[idx] = snap
                }
                return .none

            case .toolbar(.templateSelected(let template)):
                // Toolbar's forwarded action; promote to the
                // per-page template change above.
                return .send(.templateSelected(template))

            case .toolbar:
                return .none

            case .textEditing:
                return .none
            }
        }
    }

    // MARK: - Effects

    private func refresh(notebookID: UUID) -> Effect<Action> {
        .run { send in
            do {
                // Resolve type FIRST so the screen branches correctly
                // before pagesLoaded fans out further effects (the
                // textNote path triggers loadTextBlocks from the same
                // pages-loaded action).
                if let detail = try await notebookClient.fetchNotebook(notebookID) {
                    await send(.notebookTypeResolved(detail.notebook.notebookType))
                }
                let pages = try await notebookClient.fetchPagesForNotebook(notebookID)
                await send(.pagesLoaded(pages))
            } catch {
                log.error("Notebook refresh failed: \(error.localizedDescription)")
            }
        }
        .cancellable(id: "notebookRefresh-\(notebookID.uuidString)", cancelInFlight: true)
    }

    private func loadTextBlocks(pageID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let blocks = try await notebookClient.fetchBlocksForPage(pageID)
                await send(.textBlocksLoaded(blocks))
            } catch {
                log.error("loadTextBlocks failed for page \(pageID): \(error.localizedDescription)")
            }
        }
        .cancellable(id: "textBlocksLoad-\(pageID.uuidString)", cancelInFlight: true)
    }

    private func observeStoreChanges() -> Effect<Action> {
        .run { send in
            for await _ in ModelStoreObserver.observe() {
                await send(.storeDidChange)
            }
        }
        .cancellable(id: "notebookStoreObservation", cancelInFlight: true)
    }

    private func seedFirstPage(notebookID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let snap = try await notebookClient.createPage(
                    notebookID,
                    CanvasTemplate.none.rawValue
                )
                await send(.pageCreated(snap))
            } catch {
                log.error("First-page seed failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helpers

private extension Array {
    /// Safe-index subscript — `nil` instead of trap when out of range.
    /// Used by the reducer to read the current page without crashing
    /// during mid-seed transient states.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
