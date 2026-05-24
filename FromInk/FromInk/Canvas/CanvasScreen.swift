import SwiftUI
import PencilKit
import ComposableArchitecture

private enum ActiveSheet: Identifiable {
    case lasso
    case brief
    case link
    case calendarEdit(InkTask)
    var id: String {
        switch self {
        case .lasso:              return "lasso"
        case .brief:              return "brief"
        case .link:               return "link"
        case .calendarEdit(let t): return "calendarEdit-\(t.id)"
        }
    }
}

struct CanvasScreen: View {
    var notebookID: UUID = UUID()
    /// Stable UUID for the persisted `NotePage` this canvas backs. Drives
    /// drawing/headers/links/history persistence via `NotebookClient`.
    var pageID: UUID = UUID()
    /// Display-only sibling index within the parent notebook. Used by the
    /// page navigator chrome; persistence is keyed off `pageID`.
    var pageIndex: Int = 0
    var onNearBottom: () -> Void = {}
    var onAwayFromBottom: () -> Void = {}

    @Dependency(\.notebookClient) private var notebookClient

    // TCA stores
    @State private var toolbarStore = Store(initialState: ToolbarFeature.State()) {
        ToolbarFeature()
    }
    @State private var dispatchPanelStore = Store(
        initialState: DispatchPanelFeature.State()
    ) {
        DispatchPanelFeature()
    }

    // Legacy state still needed until full CanvasFeature migration
    @State private var currentDrawing = PKDrawing()
    @State private var activeTemplate: CanvasTemplate = .none
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
    @State private var lassoTask: InkTask? = nil
    @State private var isRecognizing = false
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
                        activeSheet = .calendarEdit(task)
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
                lassoTask = nil
                isRecognizing = true
                activeSheet = .lasso
                Task {
                    defer { isRecognizing = false }
                    let result = await InkTaskExtractor.extract(image: image, scope: .single)
                    lassoTask = result.tasks.first
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

                ToolbarWiringView(
                    store: toolbarStore,
                    zones: ToolbarZoneConfig.standard(isCompact: sizeClass == .compact)
                )
                    .frame(maxHeight: .infinity, alignment: .center)
                    .frame(
                        maxWidth: .infinity,
                        alignment: toolbarSide == .left ? .leading : .trailing
                    )

                // Panel presentation — driven by toolbarStore.openPanel
                if toolbarStore.openPanel != nil {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toolbarStore.send(.panelDismissed)
                        }
                }

                if let panel = toolbarStore.openPanel {
                    toolbarPanel(panel)
                }

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
            }
            .onAppear {
                toolbarStore.send(.onAppear)
            }
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
        }
        .onChange(of: dispatchPanelStore.openLinkURL) { _, url in
            guard let url else { return }
            activeLinkURL = url
            dispatchPanelStore.send(.dismissed)
        }
        .onChange(of: toolbarStore.isDispatchRequested) { _, requested in
            guard requested else { return }
            syncDispatchPanelData()
            dispatchPanelStore.send(.presented)
            toolbarStore.send(.dispatchAcknowledged)
        }
        .task(id: pageID) { await loadPageOnAppear() }
        .onDisappear {
            // Save-on-navigate: flush whatever's in the canvas right now.
            // Fires for page swipe (TabView), fullScreenCover dismiss, and
            // notebook close. The flush is awaitable but we kick it off in
            // a Task so view teardown doesn't block — the Coordinator's
            // weak ref to PKCanvasView is what makes this safe even if
            // the view is gone before the save completes.
            let bridge = canvasBridge
            Task { await bridge.flush() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Save-on-background: any non-active scene phase means the
            // user has navigated away from the app — persist before iOS
            // potentially suspends the process.
            guard phase != .active else { return }
            let bridge = canvasBridge
            Task { await bridge.flush() }
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
        case .lasso:
            LassoActionSheet(
                isLoading: isRecognizing,
                task: lassoTask ?? InkTask(title: ""),
                onDismiss: { activeSheet = nil },
                onSend: { task in
                    activeSheet = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        await routeTask(task)
                    }
                }
            )
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
        case .calendarEdit(let task):
            EventEditView(
                taskTitle: task.title,
                onSave: { result in
                    saveRoutedItem(task: task, result: result)
                    activeSheet = nil
                },
                onCancel: { activeSheet = nil }
            )
            .ignoresSafeArea()
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
    private func toolbarPanel(_ panel: PanelKind) -> some View {
        let tw = LayoutTokens.standard.toolbarWidth
        let panelGap = LayoutTokens.standard.toolbarPanelGap

        Group {
            switch panel {
            case .toolCustomization(let toolID):
                let tool: CanvasTool = CanvasTool(rawValue: toolID.rawValue) ?? .pen
                PenCustomizationPanel(
                    tool: tool,
                    settings: Binding(
                        get: { toolbarStore.toolSettings[id: toolID]?.settings ?? .default },
                        set: { toolbarStore.send(.toolSettingsChanged(toolID, $0)) }
                    ),
                    onDismiss: { toolbarStore.send(.panelDismissed) }
                )

            case .templatePicker:
                TemplatePickerPanel(
                    template: Binding(
                        get: { activeTemplate },
                        set: { activeTemplate = $0; toolbarStore.send(.panelDismissed) }
                    ),
                    onDismiss: { toolbarStore.send(.panelDismissed) }
                )

            case .canvasSettings:
                CanvasSettingsPanel(
                    onDismiss: { toolbarStore.send(.panelDismissed) }
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.leading, toolbarSide == .left ? tw + panelGap : 0)
        .padding(.trailing, toolbarSide == .right ? tw + panelGap : 0)
        .frame(maxWidth: .infinity, alignment: toolbarSide == .left ? .leading : .trailing)
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
    CanvasScreen()
}
