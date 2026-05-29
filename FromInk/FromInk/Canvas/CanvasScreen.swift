import SwiftUI
import PencilKit
import ComposableArchitecture

private enum ActiveSheet: Identifiable {
    case brief
    case link
    var id: String {
        switch self {
        case .brief: return "brief"
        case .link:  return "link"
        }
    }
}

/// Active dispatch flow. Holds the originating task (needed to build
/// the `NoteHistoryDraft` after a successful send) alongside the
/// TCA store that backs the universal Dispatch modal. Per-page
/// lifecycle by design — swiping pages dismisses an in-progress edit.
private struct DispatchFlow {
    let task: InkTask
    let store: StoreOf<DispatchFeature>
}

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

    /// Loaded once from `NotePage.drawingData` on `.task` and passed to
    /// `CanvasView` as `initialDrawingData`. Persisted updates flow
    /// out of the Coordinator directly via `NotebookClient.saveDrawing`,
    /// so this state is read-only after the initial load.
    @State private var loadedDrawingData: Data? = nil
    @State private var hasLoadedDrawing = false

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
    @State private var activeSheet: ActiveSheet? = nil
    @State private var isAnalyzing = false
    @State private var briefSummary: String = ""
    @State private var briefTasks: [InkTask] = []
    @State private var briefOpenQuestion: String? = nil
    @State private var lassoMenuImage: UIImage? = nil
    @State private var lassoMenuRect: CGRect = .zero
    @State private var lassoContentRect: CGRect = .zero
    @State private var showLassoMenu = false
    @State private var scrollOffset: CGPoint = .zero

    // Headers (persisted via NotebookClient; UI cache of NoteHeaderSnapshot)
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

    // Routing
    @State private var routingPermissionError: String? = nil
    /// Non-nil while the universal Dispatch modal is showing for a task
    /// that needed user input (calendar route without a due date).
    @State private var dispatchFlow: DispatchFlow? = nil

    // Links (persisted via NotebookClient; UI cache of NoteLinkSnapshot)
    @State private var links: [NoteLinkSnapshot] = []
    @State private var pendingLinkContentRect: CGRect = .zero
    @State private var pendingLinkOCRText: String = ""
    @State private var isRecognizingLink = false
    @State private var activeLinkURL: URL? = nil
    @State private var editingLink: NoteLinkSnapshot? = nil


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
        let store = Store(
            initialState: DispatchFeature.State(
                tasks: [DispatchTask.single(from: task)],
                isExtracting: isExtracting
            )
        ) {
            DispatchFeature()
        }
        dispatchFlow = DispatchFlow(task: task, store: store)
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
            // Create mode — record any tasks that were sent.
            for dispatchTask in store.tasks {
                guard store.resolved[dispatchTask.id] == .sent else { continue }
                let integration = integrationAtCompletion(store: store)
                let result = RoutingResult(
                    integration: integration,
                    destinationURL: destinationURL(integration: integration, line: dispatchTask.line),
                    eventKitIdentifier: nil
                )
                saveRoutedItem(task: task, result: result)
            }
        case .cancelled:
            break
        }
        dispatchFlow = nil
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
        dispatchFlow = DispatchFlow(task: placeholder, store: store)
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
                    let text = await LassoOCR.recognize(image: image, correct: false)
                    do {
                        let snap = try await notebookClient.addHeader(pid, rect, text)
                        await MainActor.run {
                            headers.append(snap)
                            cachePreviewImage(image, for: snap.id)
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
                activeSheet = .link
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
                Color.canvas.ignoresSafeArea()
                    #if DEBUG
                    .sheet(isPresented: $showDebugSheet) { ExtractionDebugSheet() }
                    #endif

                canvasViewLayer
                    .ignoresSafeArea()

                headerIndicators
                linkIndicators

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

                dispatchSidePanelLayer

                // Universal Dispatch overlay — shown when a routed task
                // needs user input. Rendered last in the ZStack so it
                // covers all other page content while active. The
                // `.transition(.opacity)` + sibling animation produces
                // a subtle fade-in (and fade-out on dismiss); 100ms
                // linear matches the project animation rule.
                if let flow = dispatchFlow {
                    DispatchWiringView(store: flow.store)
                        .transition(.opacity)
                        .onChange(of: flow.store.completion) { _, completion in
                            guard let completion else { return }
                            handleDispatchCompletion(completion, task: flow.task, store: flow.store)
                        }
                }
            }
            // Page-level overlay — use `slow` (120ms) for the more
            // deliberate full-overlay fade. See "Loading-to-content
            // crossfade" / "Modal overlay fade-in" in CLAUDE.md.
            .animation(DesignSystem.standard.animation.slow, value: dispatchFlow == nil)
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
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .onChange(of: dispatchPanelStore.isVisible) { _, visible in
            guard visible else { return }
            syncDispatchPanelData()
        }
        .onChange(of: dispatchPanelStore.navigateToHeaderID) { _, headerID in
            guard let headerID else { return }
            if let header = headers.first(where: { $0.id == headerID }) {
                let y = max(0, header.rect.minY - 120)
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
        .onChange(of: toolbarStore.isDispatchRequested) { _, requested in
            // Toolbar store is shared across pages. Only the currently
            // visible page should react and acknowledge, otherwise
            // preloaded adjacent CanvasScreens would all present their
            // dispatch panel.
            guard requested, isCurrentPage else { return }
            syncDispatchPanelData()
            dispatchPanelStore.send(.presented)
            toolbarStore.send(.dispatchAcknowledged)
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

    /// Loads persisted ink + headers + links + history for the page on
    /// first `.task(id: pageID)` run. The drawing data is one-shot —
    /// `CanvasView` wires it into `PKCanvasView` in `makeUIView`. Saves
    /// flow back out of the Coordinator directly via
    /// `NotebookClient.saveDrawing` on the 800 ms debounce.
    private func loadPageOnAppear() async {
        guard !hasLoadedDrawing else { return }
        hasLoadedDrawing = true
        do {
            if let detail = try await notebookClient.fetchPage(pageID) {
                loadedDrawingData = detail.drawingData
                headers = detail.headers
                links = detail.links
                headerPreviewImages = [:]
                headerPreviewInsertionOrder = []
            }
        } catch {
            // Silent — empty page renders fine; next stroke save writes data.
        }
        await syncRoutedItemsAsync()
    }

    // MARK: - Dispatch Panel Bridge

    /// Initial URL to seed `LinkInputSheet` with when editing an existing
    /// link. Returns empty string for new links or for non-external
    /// destinations (page/notebook refs aren't represented as URLs).
    private var editingLinkInitialURL: String {
        guard let existing = editingLink else { return "" }
        if case .external(let url) = existing.destination {
            return url.absoluteString
        }
        return ""
    }

    /// Routes a confirmed `LinkInputSheet` URL through either the create
    /// or edit path. Extracted from the body to keep the SwiftUI type
    /// checker happy — inline this and the compiler times out.
    private func confirmLinkInput(url: URL) {
        if let existing = editingLink {
            updateExistingLink(existing, url: url)
        } else {
            createNewLink(url: url)
        }
        activeSheet = nil
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

    @ViewBuilder
    private var dispatchSidePanelLayer: some View {
        if sizeClass == .regular && dispatchPanelStore.isVisible {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dispatchPanelStore.send(.dismissed) }

            let ds = DesignSystem.standard
            DispatchPanelWiringView(store: dispatchPanelStore)
                .frame(width: ds.layout.panelWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: toolbarSide == .left ? .leading : .trailing) {
                    Rectangle()
                        .fill(ds.colors.rule)
                        .frame(width: ds.layout.borderWidth)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: toolbarSide == .left ? .trailing : .leading
                )
                .transition(.move(edge: toolbarSide == .left ? .trailing : .leading))
                .ignoresSafeArea()
        }
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
                DispatchQueue.main.async {
                    lassoMenuImage = image
                    lassoMenuRect = viewRect
                    lassoContentRect = contentRect
                    showLassoMenu = true
                }
            },
            onScrollOffsetChanged: { offset in
                DispatchQueue.main.async { scrollOffset = offset }
            },
            onScrolledAwayFromBottom: onAwayFromBottom,
            scrollTo: $canvasScrollTarget,
            headerStripOnRight: toolbarSide == .left,
            onHeaderPanelRequested: {
                syncDispatchPanelData()
                dispatchPanelStore.send(.presented)
            }
        )
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .brief:
            BriefSheet(
                isLoading: isAnalyzing,
                summary: briefSummary,
                tasks: $briefTasks,
                openQuestion: briefOpenQuestion,
                onDismiss: { activeSheet = nil },
                onSendAll: {
                    let tasksToRoute = briefTasks
                    activeSheet = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        for task in tasksToRoute {
                            await routeTask(task)
                        }
                    }
                }
            )
        case .link:
            LinkInputSheet(
                isLoading: isRecognizingLink,
                recognizedText: pendingLinkOCRText,
                initialURL: editingLinkInitialURL,
                isEditing: editingLink != nil,
                onConfirm: { url in confirmLinkInput(url: url) },
                onDismiss: {
                    editingLink = nil
                    activeSheet = nil
                }
            )
        }
    }

    @ViewBuilder
    private var headerIndicators: some View {
        ForEach(headers) { header in
            let viewX = header.rect.midX - scrollOffset.x
            let viewY = header.rect.midY - scrollOffset.y
            HeaderIndicator(header: header)
                .position(x: viewX, y: viewY)
        }
    }

    @ViewBuilder
    private var linkIndicators: some View {
        ForEach(links) { link in
            let viewX = link.rect.midX - scrollOffset.x
            let viewY = link.rect.midY - scrollOffset.y
            LinkIndicator(
                link: link,
                onTap: { onLinkTapped(link) },
                onEdit: { beginEditingLink(link) },
                onDelete: { deleteLink(link) }
            )
            .position(x: viewX, y: viewY)
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
        activeSheet = .link
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
                let snap = try await notebookClient.addLink(pid, rect, text, .external(url))
                await MainActor.run { links.append(snap) }
            } catch {
                // Silent — the link just doesn't persist.
            }
        }
    }

    private func syncDispatchPanelData() {
        dispatchPanelStore.send(
            .headersUpdated(
                headers.map { h in
                    DispatchHeaderItem(
                        id: h.id,
                        ocrText: h.ocrText.isEmpty ? nil : h.ocrText,
                        image: headerPreviewImages[h.id],
                        positionY: h.rect.minY
                    )
                }
            )
        )
        dispatchPanelStore.send(
            .linksUpdated(
                links.compactMap { l in
                    guard case .external(let url) = l.destination else { return nil }
                    return DispatchLinkItem(
                        id: l.id,
                        recognizedText: l.ocrText,
                        url: url
                    )
                }
            )
        )
        Task { await syncRoutedItemsAsync() }
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
        }
    )
}
