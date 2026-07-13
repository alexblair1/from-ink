import SwiftUI
import PencilKit
import ComposableArchitecture

struct CanvasScreen: View {
    var notebookID: UUID = UUID()
    /// Stable UUID for the persisted `NotePage` this canvas backs. Drives
    /// drawing/headers/links/history persistence via `NotebookClient`.
    var pageID: UUID = UUID()
    /// Display-only sibling index within the parent notebook. Used by the
    /// page navigator chrome; persistence is keyed off `pageID`.
    var pageIndex: Int = 0
    /// Shared toolbar store, owned by the parent `NotebookScreen` so the
    /// toolbar stays pinned across page swipes and tool selection persists
    /// across pages.
    var toolbarStore: StoreOf<ToolbarFeature>
    /// Notebook-wide template selection, owned by `NotebookScreen`. Read
    /// here; written from the template picker panel at notebook level.
    var activeTemplate: CanvasTemplate = .none
    /// True for the page the TabView is currently showing. Used to guard
    /// observers of shared toolbar state so adjacent preloaded pages
    /// don't multi-fire dispatch presentations.
    var isCurrentPage: Bool = true
    var onNearBottom: () -> Void = {}
    var onAwayFromBottom: () -> Void = {}

    @Dependency(\.notebookClient) private var notebookClient

    @State private var dispatchPanelStore = Store(
        initialState: DispatchPanelFeature.State()
    ) {
        DispatchPanelFeature()
    }

    // Legacy state still needed until full CanvasFeature migration
    @State private var currentDrawing = PKDrawing()
    @State private var strokeCount: Int = 0

    /// Loaded once from the page's ink block on `.task` and passed to
    /// `CanvasView` as `initialDrawingData`. Persisted updates flow
    /// out of the Coordinator directly via
    /// `NotebookClient.updateBlockDrawing`, so this state is read-only
    /// after the initial load.
    @State private var loadedDrawingData: Data? = nil
    @State private var hasLoadedDrawing = false

    /// The page's `.ink` `PageBlock` id — the save target after the
    /// Phase 2a cutover. Resolved during `loadPageOnAppear`: the block
    /// either exists (fresh pages seed it below; legacy pages get one
    /// from the migration inside `fetchBlocksForPage`) or is inserted
    /// here. Passed to `CanvasView`, which forwards it to the
    /// Coordinator's save paths.
    @State private var inkBlockID: UUID? = nil

    /// One-shot guard for `bindCanonicalCanvasWidth` — the notebook's
    /// canonical ink width binds to the first real canvas width this
    /// device lays out (idempotent client-side too; the bind is a
    /// no-op once `canonicalCanvasWidthIsBound`). Groundwork for the
    /// EDD §6.4 cross-device render scale.
    @State private var hasBoundCanonicalWidth = false

    /// Bridge to the `CanvasView.Coordinator`. Allows this view to
    /// persist the live `PKDrawing` from `.onDisappear` (page swipe or
    /// fullScreenCover dismiss) and on scenePhase background. Replaces
    /// the prior 800ms per-stroke debounce — strokes only persist on
    /// lifecycle transitions + a safety checkpoint every 50 strokes.
    @State private var canvasBridge = CanvasViewBridge()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("correctHandwriting") private var correctHandwriting = true
    #if DEBUG
    @State private var showDebugSheet = false
    #endif

    // Sheets
    @State private var isLinkSheetVisible: Bool = false
    @State private var lassoMenuImage: UIImage? = nil
    @State private var lassoMenuRect: CGRect = .zero
    @State private var lassoContentRect: CGRect = .zero
    @State private var showLassoMenu = false
    @State private var scrollOffset: CGPoint = .zero

    // Headers (legacy state — kept as empty array so the pre-NoteRegion
    // code paths that read it remain no-ops without breaking
    // compilation. New code reads from `regions` instead.)
    @State private var headers: [NoteHeaderSnapshot] = []
    /// Transient lasso preview kept by header id — used to display the
    /// pretty handwriting image in the dispatch panel for the rest of
    /// the session. Cleared on next page open since `NoteHeader` doesn't
    /// persist images. Soft-capped at `maxPreviewImages` entries
    /// (FIFO eviction) so a marathon session marking many headers doesn't
    /// retain hundreds of multi-MB UIImages indefinitely.
    @State private var headerPreviewImages: [UUID: UIImage] = [:]
    @State private var headerPreviewInsertionOrder: [UUID] = []
    private static let maxPreviewImages = 50
    @State private var canvasScrollTarget: CGPoint? = nil

    /// Unified region records loaded from `NoteRegion`. The canvas
    /// renders `RegionIndicator` for each one; `syncDispatchPanelData`
    /// translates the slice that carries a header / external URL into
    /// the dispatch panel's existing `DispatchHeaderItem` /
    /// `DispatchLinkItem` shapes so the panel keeps working without
    /// its own NoteRegion refactor.
    @State private var regions: [NoteRegionSnapshot] = []

    // Routing
    @State private var routingPermissionError: String? = nil
    /// Hoisted to NotebookScreen so the modal renders above the toolbar
    /// and close button. Bound here so this page can present and read
    /// back the active store while OCR / extraction tasks complete.
    @Binding var dispatchFlow: DispatchFlow?
    /// Hoisted to NotebookScreen for the same reason as `dispatchFlow`.
    /// The page builds a `BriefRequest` whose `onSendAll` captures
    /// `routeTask` so per-page routing still works after the hoist.
    @Binding var briefRequest: BriefRequest?
    /// The current page's dispatch panel store, hoisted to NotebookScreen
    /// (regular width only) so the side panel renders above the close
    /// button + toolbar instead of under them. Retained across dismiss so
    /// the outgoing card can render during slide-out; cleared on page
    /// swipe. Compact width still presents via the `.sheet` below.
    @Binding var dispatchPanelPresentation: StoreOf<DispatchPanelFeature>?
    /// Visibility signal for the hoisted panel. A plain Bool (not the
    /// store's `isVisible`) so NotebookScreen reliably re-renders and runs
    /// its open/close slide animation. Toggled here from the store's state.
    @Binding var dispatchPanelVisible: Bool

    // Links (persisted via NotebookClient; UI cache of NoteLinkSnapshot)
    @State private var links: [NoteLinkSnapshot] = []
    @State private var pendingLinkContentRect: CGRect = .zero
    @State private var pendingLinkOCRText: String = ""
    @State private var isRecognizingLink = false
    @State private var activeLinkURL: URL? = nil
    @State private var editingLink: NoteLinkSnapshot? = nil

    // Region edit / manage state
    //
    // `managingRegionID` drives the confirmation dialog that opens when
    // the user taps a region's ellipsis chip. `editingHeaderRegionID`
    // drives a header text editor modal. `editingRegionLinkID` reuses
    // the existing `LinkInputSheet` for region-link edits — the
    // confirmLinkInput path branches on which of these is set.
    @State private var managingRegionID: UUID? = nil
    @State private var editingHeaderRegionID: UUID? = nil
    @State private var pendingHeaderText: String = ""
    @State private var editingRegionLinkID: UUID? = nil

    /// Captured from `lassoContentRect` when the lasso menu's
    /// "Task & Brief" action presents the dispatch flow. Used by
    /// `handleDispatchCompletion` to anchor a `NoteRegion` to the
    /// freshly-created EventKit item, so the lasso → event flow
    /// produces a visible bounding box on the canvas (parity with
    /// the lasso → header flow). nil when no lasso-originated
    /// dispatch is in flight.
    @State private var pendingLassoEventRect: CGRect? = nil


    // MARK: - Routing

    private func routeTask(_ task: InkTask) async {
        for destination in task.destinations {
            do {
                switch destination {
                case .reminders:
                    let result = try await RoutingService.shared.routeToReminders(task)
                    saveRoutedItem(task: task, result: result)
                case .calendar:
                    let outcome = try await RoutingService.shared.routeToCalendar(task)
                    switch outcome {
                    case .success(let result):
                        saveRoutedItem(task: task, result: result)
                    case .needsCalendarUI:
                        presentDispatchFlow(for: task)
                    }
                case .linear, .slack, .mail, .messages, .contacts:
                    break  // stub — covered by future integration issues
                }
            } catch let error as RoutingError {
                if case .userCancelled = error { continue }
                routingPermissionError = error.errorDescription
            } catch {
                routingPermissionError = error.localizedDescription
            }
        }
    }

    /// Builds the universal Dispatch store seeded with the originating
    /// task as a single line. The reducer's `.onAppear` seeds
    /// `calendarStart` to `cal.now()` — today, current moment — so this
    /// call site never touches `Date()`. Destination defaults to
    /// `.calendar`; the user can flip to Reminders or Mail inside the
    /// modal.
    ///
    /// `isExtracting: true` opens the modal immediately with an inline
    /// "Reading your notes…" placeholder in the line section — used by
    /// the lasso flow so the user gets a responsive modal before OCR
    /// completes. The caller is then responsible for sending
    /// `.extractionCompleted(line)` to the store when extraction lands.
    private func presentDispatchFlow(for task: InkTask, isExtracting: Bool = false) {
        var initial = DispatchFeature.State(
            tasks: [DispatchTask.single(from: task)],
            isExtracting: isExtracting
        )
        // Pass the source notebook + page so the resulting EK item
        // auto-links back via `.generatedFromInk`. The link surfaces
        // on the home brief as already-linked to this notebook on
        // next refresh.
        initial.sourceNotebookID = notebookID
        initial.sourcePageID = pageID
        let store = Store(initialState: initial) {
            DispatchFeature()
        }
        dispatchFlow = DispatchFlow(
            task: task,
            store: store,
            onCompletion: { completion in
                handleDispatchCompletion(completion, task: task, store: store)
            }
        )
    }

    /// Bridges the Dispatch completion signal back to the routing
    /// pipeline. The chosen destination at completion time decides
    /// which `Integration` the resulting `NoteHistoryDraft` records —
    /// the user may have switched from Calendar to Reminders mid-modal.
    ///
    /// Edit mode (`store.mode.isEditing`) is a different completion
    /// shape: the routed item ALREADY exists in history (that's what
    /// the user tapped to get here), so we don't write a new
    /// `NoteHistoryDraft`. Instead we refresh the panel so any
    /// title / date changes the user saved propagate up to the
    /// visible list.
    private func handleDispatchCompletion(
        _ completion: DispatchFeature.State.Completion,
        task: InkTask,
        store: StoreOf<DispatchFeature>
    ) {
        switch completion {
        case .finished where store.mode.isEditing:
            // Edit mode — the row already exists. Pull fresh data so
            // any title / date edits the user committed show up in
            // the panel without us re-recording the routing.
            syncDispatchPanelData()
        case .finished:
            // Create mode — record any tasks that were sent. We pull
            // the title from `dispatchTask.line` (what the user
            // confirmed in the modal) rather than the outer `task.title`
            // (often empty for lasso-originated flows that seed an
            // InkTask with no title until OCR resolves later). The EK
            // identifier comes from the store's resolvedEKIdentifiers
            // map, populated when sendCompleted fires with a non-nil id.
            let integration = integrationAtCompletion(store: store)
            let sentTasks = store.tasks.filter { store.resolved[$0.id] == .sent }

            for dispatchTask in sentTasks {
                let ekID = store.resolvedEKIdentifiers[dispatchTask.id]
                let routedTask = InkTask(title: dispatchTask.line)
                let result = RoutingResult(
                    integration: integration,
                    destinationURL: destinationURL(integration: integration, line: dispatchTask.line),
                    eventKitIdentifier: ekID
                )
                saveRoutedItem(task: routedTask, result: result)
            }

            // Anchor a NoteRegion to the freshly-created EK item so
            // the canvas grows a visible bounding box (parity with the
            // lasso → header flow). Calendar/Reminders only — Mail has
            // no EK item to anchor to. We anchor to the FIRST sent
            // task only: lasso flows are single-task by construction,
            // and a multi-task brief shouldn't reuse the lasso geometry
            // for every task.
            let regionRect = pendingLassoEventRect
            pendingLassoEventRect = nil
            if let rect = regionRect,
               integration == .calendar || integration == .reminders,
               let firstSent = sentTasks.first,
               let ekID = store.resolvedEKIdentifiers[firstSent.id] {
                let pid = pageID
                Task {
                    do {
                        let snap = try await notebookClient.addRegion(
                            pid, rect, nil, nil, nil, ekID
                        )
                        await MainActor.run { regions.append(snap) }
                    } catch {
                        // Silent — the EK item still exists in the
                        // user's calendar; only the canvas anchor
                        // failed to persist.
                    }
                }
            }
        case .cancelled:
            // User backed out of the dispatch flow — release any
            // captured rect so the NEXT lasso event doesn't reuse
            // stale geometry.
            pendingLassoEventRect = nil
        }
        // Lifecycle (dispatchFlow = nil) is owned by NotebookScreen,
        // which clears the binding when the store reports a completion.
    }

    /// Presents the universal Dispatch modal in edit mode for an
    /// existing routed calendar item. The reducer's
    /// `openForEditingEvent` action fetches the live `EKEvent` via
    /// `EventKitService.fetchEventDraft` and populates state on the
    /// `editingEventLoaded` follow-up. If the fetch fails (event
    /// deleted out of band, permission revoked), the modal stays
    /// open showing the error banner; the user can cancel to dismiss.
    ///
    /// **Placeholder InkTask:** edit mode has no originating capture,
    /// but `DispatchFlow.task` and `DispatchTask.originatingTask` are
    /// non-optional today (the create path always has one). We
    /// synthesize a placeholder so the types line up. It's unused —
    /// `handleDispatchCompletion`'s edit branch never reads `task`
    /// because the routed item already exists. A future refactor
    /// could split `DispatchFlow` into `.create(task, store)` /
    /// `.edit(store)` variants; for v1 a placeholder + the comment
    /// that names it is the lower-churn choice.
    ///
    /// `onCompletion` captures `placeholder` and `store` so the
    /// hoisted NotebookScreen-level renderer can invoke this page's
    /// completion logic without needing per-page wiring.
    private func presentDispatchEditFlow(for item: DispatchRoutedItem) {
        guard let identifier = item.eventKitIdentifier else { return }
        let placeholder = InkTask(title: item.title)
        let store = Store(
            initialState: DispatchFeature.State(
                tasks: [DispatchTask(line: item.title, originatingTask: placeholder)]
            )
        ) {
            DispatchFeature()
        }
        store.send(.openForEditingEvent(identifier))
        dispatchFlow = DispatchFlow(
            task: placeholder,
            store: store,
            onCompletion: { completion in
                handleDispatchCompletion(completion, task: placeholder, store: store)
            }
        )
    }

    private func integrationAtCompletion(store: StoreOf<DispatchFeature>) -> Integration {
        store.currentIntegration
    }

    private func destinationURL(integration: Integration, line: String) -> String {
        // The actual EventKit identifier isn't carried through the
        // dispatch state — store the destination kind in the URL so the
        // dispatch panel can group history correctly.
        switch integration {
        case .calendar:  return "x-apple-calevent://dispatch"
        case .reminders: return "x-apple-reminderkit://dispatch"
        case .mail:      return "mailto://dispatch"
        default:         return ""
        }
    }

    private func saveRoutedItem(task: InkTask, result: RoutingResult) {
        // Records the routing event as a `NoteHistoryEntry` with kind
        // `.taskRouted`. Replaces the legacy `RoutedItem` write — flat
        // task fields on `NoteHistoryEntry` carry the same data plus
        // gain a page parent for cascade-delete + per-page filtering.
        let draft = NoteHistoryDraft(
            kind: .routed,
            taskTitle: task.title,
            taskDestination: result.integration.rawValue,
            taskDestinationURL: result.destinationURL,
            taskEventKitIdentifier: result.eventKitIdentifier
        )
        let pageID = pageID
        Task {
            do {
                _ = try await notebookClient.recordHistory(pageID, draft)
                // Refresh dispatch panel so the calendar/reminder tab
                // updates without waiting for the user to reopen it.
                await syncRoutedItemsAsync()
            } catch {
                routingPermissionError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func lassoMenu(in geo: GeometryProxy) -> some View {
        let menuBarHeight: CGFloat = 48
        let gap: CGFloat = 12
        let menuY = lassoMenuRect.minY > menuBarHeight + gap + 20
            ? lassoMenuRect.minY - gap - menuBarHeight / 2
            : lassoMenuRect.maxY + gap + menuBarHeight / 2
        let menuX = min(max(lassoMenuRect.midX, 120), geo.size.width - 120)
        LassoMenuBar(
            onTaskBrief: {
                guard let image = lassoMenuImage else { return }
                showLassoMenu = false
                // Stash the lasso rect for the dispatch completion
                // handler — when the user sends to Calendar/Reminders
                // we anchor a NoteRegion here with the resulting EK
                // identifier so the canvas grows a visible bounding box.
                pendingLassoEventRect = lassoContentRect
                // Present Dispatch immediately with the line section in
                // its extracting state — the user sees the modal land
                // right away rather than a 200–500ms blank wait while
                // OCR runs. The store reference is captured here so a
                // dismiss-then-reopen during OCR doesn't redirect this
                // result to a different (newer) modal.
                presentDispatchFlow(for: InkTask(title: ""), isExtracting: true)
                let store = dispatchFlow?.store
                Task {
                    let result = await InkTaskExtractor.extract(image: image, scope: .single)
                    let line = result.tasks.first?.title ?? ""
                    await MainActor.run {
                        store?.send(.extractionCompleted(line))
                    }
                }
            },
            onMarkHeader: {
                guard let image = lassoMenuImage else { return }
                showLassoMenu = false
                let rect = lassoContentRect
                let pid = pageID
                Task {
                    let raw = await LassoOCR.recognize(image: image, correct: false)
                    // The data model identifies a region as a header by
                    // `headerOCRText != nil`. If Vision returns empty
                    // text the user's "Mark Header" intent would be
                    // silently dropped (region stored with empty header,
                    // snapshot strips it to nil, dispatch panel filter
                    // skips it). Fall back to a localized placeholder
                    // the user can rename via the existing edit sheet.
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let headerText = trimmed.isEmpty
                        ? AppStrings.RegionIndicator.headerOCRFallback
                        : trimmed
                    do {
                        let snap = try await notebookClient.addRegion(
                            pid, rect, headerText, nil, nil, nil
                        )
                        await MainActor.run {
                            regions.append(snap)
                        }
                    } catch {
                        // Silent — the header drop just doesn't persist.
                    }
                }
            },
            onLink: {
                guard let image = lassoMenuImage else { return }
                showLassoMenu = false
                pendingLinkContentRect = lassoContentRect
                pendingLinkOCRText = ""
                isRecognizingLink = true
                isLinkSheetVisible = true
                Task {
                    defer { isRecognizingLink = false }
                    pendingLinkOCRText = await LassoOCR.recognize(image: image, correct: true)
                }
            },
            onCopyText: { showLassoMenu = false },
            onSearch: { showLassoMenu = false },
            onShare: { showLassoMenu = false }
        )
        .position(x: menuX, y: menuY)
    }

    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Bridge: ToolID → CanvasTool for the legacy CanvasView binding.
    /// Uses rawValue matching so adding a new ToolID doesn't require a switch change.
    private var activeTool: CanvasTool {
        CanvasTool(rawValue: toolbarStore.activeToolID.rawValue) ?? .pen
    }

    private var activeSettings: PenSettings {
        toolbarStore.activeSettings
    }

    private var toolbarSide: ToolbarSide {
        toolbarStore.side
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                DesignSystem.standard.colors.paper.ignoresSafeArea()
                    #if DEBUG
                    .sheet(isPresented: $showDebugSheet) { ExtractionDebugSheet() }
                    #endif
                    // Canonical-width bind (EDD §6.4 groundwork) — needs
                    // `geo`, so it rides the background layer inside the
                    // GeometryReader rather than the outer lifecycle chain.
                    .task(id: geo.size.width) {
                        await bindCanonicalWidthIfNeeded(width: geo.size.width)
                    }

                canvasViewLayer
                    .ignoresSafeArea()

                regionIndicators

                if showLassoMenu {
                    // Selection highlight — stays visible while menu is up
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        }
                        .frame(width: lassoMenuRect.width, height: lassoMenuRect.height)
                        .position(x: lassoMenuRect.midX, y: lassoMenuRect.midY)
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.linear(duration: 0.08)) { showLassoMenu = false }
                        }

                    lassoMenu(in: geo)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: showLassoMenu)
                }
            }
            // Page-level dispatch modal is rendered at NotebookScreen so
            // it covers the toolbar; the page only animates side panels
            // it still owns.
            .onChange(of: currentDrawing.strokes.count) { _, _ in
                pruneErasedLinks()
            }
        }
        .ignoresSafeArea()
        .sheet(
            isPresented: Binding(
                get: { sizeClass == .compact && dispatchPanelStore.isVisible },
                set: { if !$0 { dispatchPanelStore.send(.dismissed) } }
            )
        ) {
            DispatchPanelWiringView(store: dispatchPanelStore)
        }
        .sheet(isPresented: Binding(
            get: { activeLinkURL != nil },
            set: { if !$0 { activeLinkURL = nil } }
        )) {
            if let url = activeLinkURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .alert(
            "Unable to Route Task",
            isPresented: Binding(
                get: { routingPermissionError != nil },
                set: { if !$0 { routingPermissionError = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { routingPermissionError = nil }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                routingPermissionError = nil
            }
        } message: {
            if let msg = routingPermissionError { Text(msg) }
        }
        .sheet(isPresented: $isLinkSheetVisible) {
            LinkInputSheet(
                isLoading: isRecognizingLink,
                recognizedText: pendingLinkOCRText,
                initialURL: editingLinkInitialURL,
                isEditing: editingLink != nil || editingRegionLinkID != nil,
                onConfirm: { url in confirmLinkInput(url: url) },
                onDismiss: {
                    editingLink = nil
                    editingRegionLinkID = nil
                    isLinkSheetVisible = false
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { editingHeaderRegionID != nil },
                set: { if !$0 { editingHeaderRegionID = nil; pendingHeaderText = "" } }
            )
        ) {
            RegionHeaderEditSheet(
                text: $pendingHeaderText,
                onSave: { commitRegionHeaderEdit() },
                onCancel: {
                    editingHeaderRegionID = nil
                    pendingHeaderText = ""
                }
            )
        }
        .confirmationDialog(
            AppStrings.RegionIndicator.manageTitle,
            isPresented: Binding(
                get: { managingRegionID != nil },
                set: { if !$0 { managingRegionID = nil } }
            ),
            titleVisibility: .visible,
            presenting: managingRegionID
        ) { regionID in
            if let region = regions.first(where: { $0.id == regionID }) {
                if region.headerOCRText != nil {
                    Button(AppStrings.RegionIndicator.manageEditHeader) {
                        managingRegionID = nil
                        beginEditingRegionHeader(regionID)
                    }
                }
                // Surface "Edit link" for any non-`.none` destination —
                // including `.broken`, where the entire affordance is
                // "tap to repair." Restricting to `.external` was a bug
                // (broken links became unreachable via this menu).
                if region.linkDestination != .none {
                    Button(AppStrings.RegionIndicator.manageEditLink) {
                        managingRegionID = nil
                        beginEditingRegionLink(regionID)
                    }
                }
                Button(AppStrings.RegionIndicator.manageDelete, role: .destructive) {
                    managingRegionID = nil
                    deleteRegion(regionID)
                }
                Button(AppStrings.RegionIndicator.manageCancel, role: .cancel) {
                    managingRegionID = nil
                }
            }
        }
        .onChange(of: dispatchPanelStore.isVisible) { _, visible in
            if visible { syncDispatchPanelData() }
            syncDispatchHoist()
        }
        .onChange(of: sizeClass) { _, _ in
            // Regular↔compact transitions (iPad Split View / Slide Over)
            // must re-reconcile: compact presents via the `.sheet`, regular
            // via the hoisted card. Without this, resizing while open
            // double-presents (card + sheet) or drops the panel entirely.
            syncDispatchHoist()
        }
        .onChange(of: dispatchPanelStore.navigateToHeaderID) { _, headerID in
            guard let headerID else { return }
            // The dispatch panel populates header rows from `regions`
            // (see `syncDispatchPanelData`), so the navigate-to-header
            // lookup must resolve against the same source. The legacy
            // `headers` array is an empty stub post-NoteRegion migration.
            if let region = regions.first(where: { $0.id == headerID }) {
                let y = max(0, region.rect.minY - 120)
                canvasScrollTarget = CGPoint(x: 0, y: y)
            }
            dispatchPanelStore.send(.dismissed)
            dispatchPanelStore.send(.headerNavigationHandled)
        }
        .onChange(of: dispatchPanelStore.openLinkURL) { _, url in
            guard let url else { return }
            activeLinkURL = url
            dispatchPanelStore.send(.dismissed)
            dispatchPanelStore.send(.linkOpenHandled)
        }
        .onChange(of: dispatchPanelStore.openRoutedItem) { _, item in
            // Edit-existing-event flow. Calendar items with a live EK
            // identifier and not-yet-deleted state can round-trip; the
            // rest just dismiss the panel without opening the modal
            // (no edit affordance for reminders/mail yet).
            guard let item else { return }
            if item.destinationKind == .calendar,
               item.eventKitIdentifier != nil,
               !item.isDeleted {
                presentDispatchEditFlow(for: item)
            }
            dispatchPanelStore.send(.dismissed)
            dispatchPanelStore.send(.routedItemOpenHandled)
        }
        .onChange(of: dispatchPanelStore.addRequestedTab) { _, tab in
            // Forwarded "+ Add …" affordance from the dispatch panel.
            // The panel exposes the intent per tab; presenting the
            // matching add flow (link input / calendar / reminder draft)
            // is wired here. Consume the signal so a repeat tap on the
            // same tab re-fires (onChange equality-dedupes otherwise).
            // TODO: present the add flow per `tab` (.links → LinkInputSheet,
            // .calendar/.reminders → routed-item draft). Not yet wired.
            guard tab != nil else { return }
            dispatchPanelStore.send(.addRequestHandled)
        }
        .onChange(of: toolbarStore.isDispatchRequested) { _, requested in
            // Toolbar store is shared across pages. Only the currently
            // visible page should react and acknowledge, otherwise
            // preloaded adjacent CanvasScreens would all present their
            // dispatch panel.
            guard requested, isCurrentPage else { return }
            if dispatchPanelStore.isVisible {
                dispatchPanelStore.send(.dismissed)
            } else {
                syncDispatchPanelData()
                dispatchPanelStore.send(.presented)
            }
            toolbarStore.send(.dispatchAcknowledged)
        }
        .onChange(of: toolbarStore.isUndoRequested) { _, requested in
            // Same shared-toolbar guard as dispatch: only the current
            // page's PKCanvasView should consume + acknowledge.
            guard requested, isCurrentPage else { return }
            canvasBridge.undo()
            toolbarStore.send(.undoAcknowledged)
        }
        .onChange(of: toolbarStore.isRedoRequested) { _, requested in
            guard requested, isCurrentPage else { return }
            canvasBridge.redo()
            toolbarStore.send(.redoAcknowledged)
        }
        .task(id: pageID) { await loadPageOnAppear() }
        .onDisappear {
            // Save-on-navigate: capture the current drawing SYNCHRONOUSLY
            // before SwiftUI deallocates the underlying PKCanvasView.
            // The snapshot owns its values (PKDrawing is a value type;
            // NotebookClient is a struct of closures), so persistence in
            // the unstructured Task can't be raced by view teardown.
            // Fires for page swipe (TabView), fullScreenCover dismiss,
            // and notebook close.
            guard let snapshot = canvasBridge.snapshotForFlush() else { return }
            Task { await CanvasViewBridge.persist(snapshot) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Save-on-background: any non-active scene phase means the
            // user has navigated away from the app — persist before iOS
            // potentially suspends the process. Same synchronous-snapshot
            // pattern as above.
            guard phase != .active,
                  let snapshot = canvasBridge.snapshotForFlush() else { return }
            Task { await CanvasViewBridge.persist(snapshot) }
        }
    }

    /// Bind the notebook's canonical ink width to the first real canvas
    /// width this device lays out (EDD §6.4 groundwork — Phase 2a). On
    /// the authoring device the render scale stays 1.0; the bound width
    /// is what a DIFFERENT viewport later divides by to scale ink.
    /// One-shot per screen instance; the live client is idempotent too
    /// (no-op once `canonicalCanvasWidthIsBound`), so preloaded sibling
    /// pages racing this bind are harmless.
    private func bindCanonicalWidthIfNeeded(width: CGFloat) async {
        guard !hasBoundCanonicalWidth, width > 0 else { return }
        hasBoundCanonicalWidth = true
        try? await notebookClient.bindCanonicalCanvasWidth(notebookID, Double(width))
    }

    /// Loads persisted ink + headers + links + history for the page on
    /// first `.task(id: pageID)` run. The drawing data is one-shot —
    /// `CanvasView` applies it to `PKCanvasView` once. Saves flow back
    /// out of the Coordinator via `NotebookClient.updateBlockDrawing`
    /// against `inkBlockID` (Phase 2a cutover — hybrid_page_edd §6
    /// Phase 2: ink lives on the page's `.ink` block, and legacy
    /// `NotePage.drawingData` migrates inside `fetchBlocksForPage`).
    private func loadPageOnAppear() async {
        guard !hasLoadedDrawing else { return }
        hasLoadedDrawing = true
        do {
            if let detail = try await notebookClient.fetchPage(pageID) {
                regions = detail.regions
                // Legacy `headers` / `links` state stays empty —
                // canvas rendering reads from `regions` only.
                headers = []
                links = []
                headerPreviewImages = [:]
                headerPreviewInsertionOrder = []
            }
            // Block-first ink load. fetchBlocksForPage migrates any
            // legacy page-level payload before returning, so a
            // pre-cutover page arrives here already holding its ink
            // block. A genuinely fresh page seeds one so the save
            // paths always have a target.
            let blocks = try await notebookClient.fetchBlocksForPage(pageID)
            if let ink = blocks.first(where: { $0.kind == .ink }) {
                inkBlockID = ink.id
                loadedDrawingData = try await notebookClient.loadBlockDrawing(ink.id)
            } else {
                let seeded = try await notebookClient.insertBlock(pageID, .ink, nil)
                inkBlockID = seeded.id
                loadedDrawingData = nil
            }
        } catch {
            // Silent — empty page renders fine; the ink block seed
            // retries via the save-skip log path if it failed here.
        }
        await syncRoutedItemsAsync()
    }

    // MARK: - Dispatch Panel Bridge

    /// Initial URL to seed `LinkInputSheet` with when editing an existing
    /// link. Returns empty string for new links or for non-external
    /// destinations (page/notebook refs aren't represented as URLs).
    private var editingLinkInitialURL: String {
        if let regionID = editingRegionLinkID,
           let region = regions.first(where: { $0.id == regionID }),
           case .external(let url) = region.linkDestination {
            return url.absoluteString
        }
        guard let existing = editingLink else { return "" }
        if case .external(let url) = existing.destination {
            return url.absoluteString
        }
        return ""
    }

    /// Routes a confirmed `LinkInputSheet` URL through three paths:
    /// region-link edit (most common path now that NoteLink is gone),
    /// legacy NoteLink edit (no-op — `editingLink` is never set after
    /// the NoteRegion migration), or create-new-region. Extracted from
    /// the body to keep the SwiftUI type checker happy — inline this
    /// and the compiler times out.
    private func confirmLinkInput(url: URL) {
        if let regionID = editingRegionLinkID {
            updateRegionLink(regionID: regionID, url: url)
        } else if let existing = editingLink {
            updateExistingLink(existing, url: url)
        } else {
            createNewLink(url: url)
        }
        isLinkSheetVisible = false
    }

    private func updateRegionLink(regionID: UUID, url: URL) {
        editingRegionLinkID = nil
        Task {
            do {
                let snap = try await notebookClient.updateRegionLink(
                    regionID,
                    .external(url)
                )
                await MainActor.run {
                    if let idx = regions.firstIndex(where: { $0.id == regionID }) {
                        regions[idx] = snap
                    }
                    refreshDispatchPanelIfVisible()
                }
            } catch {
                // Silent — UI stays at the prior value.
            }
        }
    }

    private func updateExistingLink(_ existing: NoteLinkSnapshot, url: URL) {
        let updated = NoteLinkSnapshot(
            id: existing.id,
            pageID: existing.pageID,
            ocrText: existing.ocrText,
            rect: existing.rect,
            createdAt: existing.createdAt,
            destination: .external(url)
        )
        if let idx = links.firstIndex(where: { $0.id == existing.id }) {
            links[idx] = updated
        }
        editingLink = nil
        let linkID = existing.id
        Task { try? await notebookClient.updateLink(linkID, .external(url)) }
    }


    private var canvasViewLayer: some View {
        CanvasView(
            tool: Binding(
                get: { activeTool },
                set: { _ in } // tool changes flow through the store, not the binding
            ),
            penSettings: activeSettings,
            template: activeTemplate,
            pageID: pageID,
            inkBlockID: inkBlockID,
            initialDrawingData: loadedDrawingData,
            notebookClient: notebookClient,
            bridge: canvasBridge,
            onTwoFingerHoldBegan: { toolbarStore.send(.twoFingerHoldBegan) },
            onTwoFingerHoldEnded: { toolbarStore.send(.twoFingerHoldEnded) },
            onPencilDoubleTap: { toolbarStore.send(.pencilDoubleTapped) },
            onStrokeCountChanged: { count in
                // PencilKit delegate callbacks can fire while SwiftUI is
                // mid-render (especially scrollViewDidScroll during a
                // layout pass). Mutating @State synchronously triggers
                // "Modifying state during view update" warnings. Defer
                // to the next runloop tick to break out of the cycle.
                DispatchQueue.main.async {
                    strokeCount = count
                    toolbarStore.send(.boltVisibilityChanged(count >= 10))
                }
            },
            onDrawingChanged: { drawing in
                DispatchQueue.main.async { currentDrawing = drawing }
            },
            onScrolledNearBottom: onNearBottom,
            onLassoReady: { image, viewRect, contentRect in
                // No gate here — the Coordinator already decided at
                // lasso-BEGIN time whether this is a branded session
                // via `wantsBrandedLasso` → `awaitingLassoSelection`.
                // `onLassoReady` only fires for branded sessions; bare
                // `.lasso` sessions don't invoke this callback at all.
                DispatchQueue.main.async {
                    lassoMenuImage = image
                    lassoMenuRect = viewRect
                    lassoContentRect = contentRect
                    showLassoMenu = true
                }
            },
            wantsBrandedLasso: toolbarStore.activeToolID == .region,
            onScrollOffsetChanged: { offset in
                DispatchQueue.main.async { scrollOffset = offset }
            },
            onScrolledAwayFromBottom: onAwayFromBottom,
            scrollTo: $canvasScrollTarget
        )
    }

    @ViewBuilder
    private var regionIndicators: some View {
        ForEach(regions) { region in
            // Render only when the region's rect still anchors to
            // handwriting. Orphaned regions (handwriting erased) are
            // surfaced through the dispatch panel, not the canvas.
            if region.isAnchored {
                let viewX = region.rect.midX - scrollOffset.x
                let viewY = region.rect.midY - scrollOffset.y
                let regionID = region.id
                RegionIndicator(
                    model: RegionIndicator.Model(
                        snapshot: region,
                        onEditHeaderTapped: { beginEditingRegionHeader(regionID) },
                        onEditLinkTapped: { beginEditingRegionLink(regionID) },
                        onEditEventTapped: { beginEditingRegionEvent(regionID) },
                        onManageTapped: { managingRegionID = regionID }
                    )
                )
                .position(x: viewX, y: viewY)
            }
        }
    }

    private func beginEditingRegionHeader(_ regionID: UUID) {
        guard let region = regions.first(where: { $0.id == regionID }) else { return }
        editingHeaderRegionID = regionID
        pendingHeaderText = region.headerOCRText ?? ""
    }

    private func beginEditingRegionLink(_ regionID: UUID) {
        guard let region = regions.first(where: { $0.id == regionID }) else { return }
        editingRegionLinkID = regionID
        pendingLinkContentRect = region.rect
        // Read the link's recognized text from `linkRecognizedText`
        // (not `headerOCRText`) — they're separate fields now so a
        // link with no recognized text isn't treated as a header.
        pendingLinkOCRText = region.linkRecognizedText ?? ""
        isRecognizingLink = false
        isLinkSheetVisible = true
    }

    /// Routes a tap on the region's calendar badge to the existing
    /// dispatch edit flow. Mirrors `presentDispatchEditFlow(for:)`
    /// from the dispatch panel path — same modal, same edit semantics
    /// (destination strip hidden because `model.isEditing == true`).
    /// Silent no-op if the region has no EK identifier; that shouldn't
    /// happen because the badge only renders when `eventKitIdentifier
    /// != nil`, but the guard keeps the function safe to call
    /// unconditionally.
    private func beginEditingRegionEvent(_ regionID: UUID) {
        guard let region = regions.first(where: { $0.id == regionID }),
              let identifier = region.eventKitIdentifier else { return }
        let placeholder = InkTask(title: region.headerOCRText ?? "")
        let store = Store(
            initialState: DispatchFeature.State(
                tasks: [DispatchTask(line: placeholder.title, originatingTask: placeholder)]
            )
        ) {
            DispatchFeature()
        }
        store.send(.openForEditingEvent(identifier))
        dispatchFlow = DispatchFlow(
            task: placeholder,
            store: store,
            onCompletion: { completion in
                handleDispatchCompletion(completion, task: placeholder, store: store)
            }
        )
    }

    private func deleteRegion(_ regionID: UUID) {
        regions.removeAll { $0.id == regionID }
        refreshDispatchPanelIfVisible()
        Task { try? await notebookClient.deleteRegion(regionID) }
    }

    private func commitRegionHeaderEdit() {
        guard let regionID = editingHeaderRegionID else { return }
        let trimmed = pendingHeaderText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String? = trimmed.isEmpty ? nil : trimmed
        editingHeaderRegionID = nil
        pendingHeaderText = ""
        Task {
            do {
                let snap = try await notebookClient.updateRegionHeader(regionID, text)
                await MainActor.run {
                    if let idx = regions.firstIndex(where: { $0.id == regionID }) {
                        regions[idx] = snap
                    }
                    refreshDispatchPanelIfVisible()
                }
            } catch {
                // Silent — UI just stays at the prior value.
            }
        }
    }

    /// Fan-out for region mutations: if the dispatch panel is open,
    /// re-translate `regions` into the panel's header/link items so
    /// header text edits, link changes, and deletes appear without
    /// the user having to close + reopen the panel. No-op when the
    /// panel is hidden — `syncDispatchPanelData` runs on next reveal
    /// via `onChange(of: dispatchPanelStore.isVisible)`.
    private func refreshDispatchPanelIfVisible() {
        guard dispatchPanelStore.isVisible else { return }
        syncDispatchPanelData()
    }

    /// Reconciles the hoisted side-panel state with the store + size class.
    /// The card is hoisted to NotebookScreen only in regular width on the
    /// current page; compact width falls back to the `.sheet`. Idempotent —
    /// safe to call from both the visibility and size-class observers. Only
    /// the current page touches the shared hoist bindings so preloaded
    /// neighbors (which share them) don't race the current page.
    private func syncDispatchHoist() {
        guard isCurrentPage else { return }
        guard sizeClass == .regular else {
            dispatchPanelVisible = false
            return
        }
        if dispatchPanelStore.isVisible {
            // Retain the store; toggle the explicit visibility Bool (a real
            // @State in NotebookScreen) so the slide animates.
            dispatchPanelPresentation = dispatchPanelStore
            dispatchPanelVisible = true
        } else {
            dispatchPanelVisible = false
        }
    }

    private func onLinkTapped(_ link: NoteLinkSnapshot) {
        if case .external(let url) = link.destination {
            activeLinkURL = url
        }
    }

    private func beginEditingLink(_ link: NoteLinkSnapshot) {
        editingLink = link
        pendingLinkOCRText = link.ocrText
        isRecognizingLink = false
        isLinkSheetVisible = true
    }

    /// FIFO cache insert with soft cap. When the cache is full we drop
    /// the oldest entry — the dispatch panel for that header just shows
    /// no image (OCR text still renders). User-visible degradation is
    /// only "the very oldest of many lasso previews stops showing its
    /// pretty preview"; everything else still works.
    private func cachePreviewImage(_ image: UIImage, for id: UUID) {
        if headerPreviewImages[id] == nil {
            headerPreviewInsertionOrder.append(id)
        }
        headerPreviewImages[id] = image
        while headerPreviewInsertionOrder.count > Self.maxPreviewImages {
            let evictID = headerPreviewInsertionOrder.removeFirst()
            headerPreviewImages.removeValue(forKey: evictID)
        }
    }

    /// Removes links whose ink has been fully erased. Synchronous local
    /// filter at stroke-change rate; the persisted `notebookClient.deleteLink`
    /// calls fire async so we don't block the UI on disk writes.
    private func pruneErasedLinks() {
        let survivors = links.filter { link in
            currentDrawing.strokes.contains { stroke in
                link.rect.intersects(stroke.renderBounds)
            }
        }
        let removed = links.filter { l in
            !survivors.contains(where: { $0.id == l.id })
        }
        links = survivors
        for r in removed {
            let linkID = r.id
            Task { try? await notebookClient.deleteLink(linkID) }
        }
    }

    private func deleteLink(_ link: NoteLinkSnapshot) {
        let linkID = link.id
        links.removeAll { $0.id == linkID }
        Task { try? await notebookClient.deleteLink(linkID) }
    }

    private func createNewLink(url: URL) {
        let rect = pendingLinkContentRect
        let text = pendingLinkOCRText
        let pid = pageID
        Task {
            do {
                // Link's OCR text goes into `linkRecognizedText`, NOT
                // `headerOCRText`. The dispatch panel's header filter
                // uses `headerOCRText != nil` as the "is a header"
                // marker; writing the link's OCR text there would
                // surface this link as a phantom header row.
                let snap = try await notebookClient.addRegion(
                    pid,
                    rect,
                    nil,
                    text.isEmpty ? nil : text,
                    .external(url),
                    nil
                )
                await MainActor.run { regions.append(snap) }
            } catch {
                // Silent — the link just doesn't persist.
            }
        }
    }

    private func syncDispatchPanelData() {
        // Translate `regions` into the dispatch panel's existing
        // `DispatchHeaderItem` / `DispatchLinkItem` shapes so the
        // panel keeps working without its own NoteRegion refactor.
        // Header rows come from regions with non-nil `headerOCRText`;
        // link rows come from regions with an external URL. A region
        // with both contributes to both lists (intentional — the
        // panel surfaces each association independently).
        //
        // Thumbnail images are cropped on-demand from the current
        // PKDrawing rather than read from a persisted cache. The
        // crop is microseconds at typical region sizes.
        let headerItems: [DispatchHeaderItem] = regions.compactMap { r in
            guard let text = r.headerOCRText else { return nil }
            return DispatchHeaderItem(
                id: r.id,
                ocrText: text,
                image: cropPreview(for: r.rect),
                positionY: r.rect.minY
            )
        }
        dispatchPanelStore.send(.headersUpdated(headerItems))

        let linkItems: [DispatchLinkItem] = regions.compactMap { r in
            guard case .external(let url) = r.linkDestination else { return nil }
            // Read the link's recognized text from `linkRecognizedText`
            // (not `headerOCRText`). The two fields are deliberately
            // distinct so a region can be a link without also being a
            // header in the dispatch panel.
            return DispatchLinkItem(
                id: r.id,
                recognizedText: r.linkRecognizedText ?? "",
                url: url
            )
        }
        dispatchPanelStore.send(.linksUpdated(linkItems))
        Task { await syncRoutedItemsAsync() }
    }

    /// On-demand thumbnail for a region's rect — crops the current
    /// `PKDrawing` at scale 4 (matches the lasso-end render scale so
    /// the visual is consistent across creation and rehydration).
    /// Returns nil when the drawing is empty or the rect has no
    /// strokes in it.
    private func cropPreview(for rect: CGRect) -> UIImage? {
        guard !currentDrawing.strokes.isEmpty else { return nil }
        return currentDrawing.image(from: rect, scale: 4)
    }

    /// Fetches the page's task-routed history entries and pushes them
    /// into the dispatch panel as `DispatchRoutedItem` value types.
    /// Called when the panel becomes visible AND after a task is
    /// successfully routed, so the calendar/reminders tab shows the
    /// new entry without waiting for the user to dismiss + reopen.
    private func syncRoutedItemsAsync() async {
        let pageID = pageID
        do {
            let history = try await notebookClient.fetchHistoryForPage(pageID)
            let calendar = history
                .filter { $0.kind == .taskRouted && $0.taskDestination == Integration.calendar.rawValue }
                .map(DispatchRoutedItem.init(snapshot:))
            let reminders = history
                .filter { $0.kind == .taskRouted && $0.taskDestination == Integration.reminders.rawValue }
                .map(DispatchRoutedItem.init(snapshot:))
            dispatchPanelStore.send(
                .routedItemsLoaded(calendar: calendar, reminders: reminders)
            )
        } catch {
            // Silent — the dispatch panel just stays at its previous values.
        }
    }
}

// MARK: - Snapshot → DispatchRoutedItem bridge

private extension DispatchRoutedItem {
    /// Bridges a persisted `NoteHistoryEntrySnapshot` (kind == .taskRouted)
    /// into the value type the dispatch panel reducer consumes. Falls back
    /// to `taskDestinationURL` for the display title when `taskTitle` is
    /// empty (legacy entries written before the title field was reliable).
    init(snapshot: NoteHistoryEntrySnapshot) {
        self.init(
            id: snapshot.id,
            title: snapshot.taskTitle.isEmpty ? snapshot.taskDestinationURL : snapshot.taskTitle,
            destination: snapshot.taskDestination,
            destinationURL: snapshot.taskDestinationURL,
            eventKitIdentifier: snapshot.taskEventKitIdentifier,
            routedAt: snapshot.timestamp,
            isDeleted: snapshot.taskStatus == "deleted"
        )
    }
}

#Preview {
    CanvasScreen(
        toolbarStore: Store(initialState: ToolbarFeature.State()) {
            ToolbarFeature()
        },
        dispatchFlow: .constant(nil),
        briefRequest: .constant(nil),
        dispatchPanelPresentation: .constant(nil),
        dispatchPanelVisible: .constant(false)
    )
}
