import SwiftUI
import SwiftData
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
    var pageIndex: Int = 0
    var onNearBottom: () -> Void = {}
    var onAwayFromBottom: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    // Toolbar state — driven by TCA
    @State private var toolbarStore = Store(initialState: ToolbarFeature.State()) {
        ToolbarFeature()
    }

    // Legacy state still needed until full CanvasFeature migration
    @State private var currentDrawing = PKDrawing()
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

    // Headers
    @State private var headers: [CanvasHeader] = []
    @State private var showHeaderPanel = false
    @State private var canvasScrollTarget: CGPoint? = nil

    // Routing
    @State private var routingPermissionError: String? = nil

    // Links
    @State private var links: [CanvasLink] = []
    @State private var pendingLinkContentRect: CGRect = .zero
    @State private var pendingLinkOCRText: String = ""
    @State private var isRecognizingLink = false
    @State private var activeLinkURL: URL? = nil
    @State private var editingLink: CanvasLink? = nil


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
                case .linear, .github, .mail:
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
        let item = RoutedItem(
            notebookID: notebookID,
            pageIndex: pageIndex,
            sourceText: task.title,
            destination: result.integration.rawValue,
            destinationTitle: task.title,
            destinationURL: result.destinationURL,
            eventKitIdentifier: result.eventKitIdentifier
        )
        modelContext.insert(item)
        try? modelContext.save()
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
                var header = CanvasHeader(contentRect: rect, image: image)
                headers.append(header)
                Task {
                    let text = await LassoOCR.recognize(image: image, correct: false)
                    if let idx = headers.firstIndex(where: { $0.id == header.id }) {
                        headers[idx].ocrText = text
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

    /// Bridge: read the active tool from the toolbar store for CanvasView.
    private var activeTool: CanvasTool {
        // Map ToolID → CanvasTool for the legacy CanvasView binding
        switch toolbarStore.activeToolID {
        case .pen: .pen
        case .fountain: .fountain
        case .pencil: .pencil
        case .marker: .marker
        case .highlighter: .highlighter
        case .eraser: .eraser
        case .lasso: .lasso
        default: .pen
        }
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

                CanvasView(
                    tool: Binding(
                        get: { activeTool },
                        set: { _ in } // tool changes flow through the store, not the binding
                    ),
                    penSettings: activeSettings,
                    template: toolbarStore.template,
                    onTwoFingerHoldBegan: {
                        toolbarStore.send(.twoFingerHoldBegan)
                    },
                    onTwoFingerHoldEnded: {
                        toolbarStore.send(.twoFingerHoldEnded)
                    },
                    onPencilDoubleTap: {
                        toolbarStore.send(.pencilDoubleTapped)
                    },
                    onStrokeCountChanged: { toolbarStore.send(.strokeCountUpdated($0)) },
                    onDrawingChanged: { currentDrawing = $0 },
                    onScrolledNearBottom: onNearBottom,
                    onLassoReady: { image, viewRect, contentRect in
                        lassoMenuImage = image
                        lassoMenuRect = viewRect
                        lassoContentRect = contentRect
                        showLassoMenu = true
                    },
                    onScrollOffsetChanged: { scrollOffset = $0 },
                    onScrolledAwayFromBottom: onAwayFromBottom,
                    scrollTo: $canvasScrollTarget,
                    headerStripOnRight: toolbarSide == .left,
                    onHeaderPanelRequested: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showHeaderPanel = true
                        }
                    }
                )
                .ignoresSafeArea()

                // Header indicators — positioned in view space using scroll offset
                ForEach(headers) { header in
                    let viewX = header.contentRect.midX - scrollOffset.x
                    let viewY = header.contentRect.midY - scrollOffset.y
                    HeaderIndicator(header: header)
                        .position(x: viewX, y: viewY)
                }

                // Link indicators — positioned in view space using scroll offset
                ForEach(links) { link in
                    let viewX = link.contentRect.midX - scrollOffset.x
                    let viewY = link.contentRect.midY - scrollOffset.y
                    LinkIndicator(
                        link: link,
                        onTap: { activeLinkURL = link.url },
                        onEdit: {
                            editingLink = link
                            pendingLinkOCRText = link.recognizedText
                            isRecognizingLink = false
                            activeSheet = .link
                        },
                        onDelete: {
                            links.removeAll { $0.id == link.id }
                        }
                    )
                    .position(x: viewX, y: viewY)
                }

                ToolbarWiringView(store: toolbarStore)
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
                    let tw = LayoutTokens.standard.toolbarWidth
                    let panelGap: CGFloat = 8
                    // All panels: top aligned to toolbar's vertical center
                    let panelTopY = geo.size.height / 2

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
                                    get: { toolbarStore.template },
                                    set: { toolbarStore.send(.templateSelected($0)) }
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
                    .frame(maxWidth: .infinity,
                           alignment: toolbarSide == .left ? .leading : .trailing)
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

                // Header panel tap-away dismiss
                if showHeaderPanel {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showHeaderPanel = false
                            }
                        }
                }

                // Header panel — always in hierarchy, slides in/out via offset
                let panelOffset: CGFloat = showHeaderPanel ? 0
                    : (toolbarSide == .left ? 420 : -420)
                HeaderPanel(
                    headers: headers,
                    links: links,
                    toolbarOnLeft: toolbarSide == .left,
                    notebookID: notebookID,
                    pageIndex: pageIndex,
                    onNavigate: { header in
                        let y = max(0, header.contentRect.minY - 120)
                        canvasScrollTarget = CGPoint(x: 0, y: y)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showHeaderPanel = false
                        }
                    },
                    onOpenLink: { url in
                        activeLinkURL = url
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showHeaderPanel = false
                        }
                    }
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity,
                       alignment: toolbarSide == .left ? .trailing : .leading)
                .offset(x: panelOffset)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showHeaderPanel)
                .allowsHitTesting(showHeaderPanel)
                .ignoresSafeArea()
            }
            .onAppear {
                toolbarStore.send(.onAppear)
            }
            .onChange(of: currentDrawing.strokes.count) { _, _ in
                // Auto-remove links whose ink has been fully erased
                links = links.filter { link in
                    currentDrawing.strokes.contains { stroke in
                        link.contentRect.intersects(stroke.renderBounds)
                    }
                }
            }
        }
        .ignoresSafeArea()
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
            switch sheet {
            case .lasso:
                LassoActionSheet(
                    isLoading: isRecognizing,
                    task: lassoTask ?? InkTask(title: ""),
                    onDismiss: { activeSheet = nil },
                    onSend: { task in
                        activeSheet = nil
                        Task {
                            // Wait for the sheet dismiss animation before presenting new UI.
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
                    initialURL: editingLink?.url.absoluteString ?? "",
                    isEditing: editingLink != nil,
                    onConfirm: { url in
                        if let existing = editingLink {
                            // Edit — update in place
                            if let idx = links.firstIndex(where: { $0.id == existing.id }) {
                                links[idx].url = url
                            }
                            editingLink = nil
                        } else {
                            // Create — append new link
                            links.append(CanvasLink(
                                contentRect: pendingLinkContentRect,
                                recognizedText: pendingLinkOCRText,
                                url: url
                            ))
                        }
                        activeSheet = nil
                    },
                    onDismiss: {
                        editingLink = nil
                        activeSheet = nil
                    }
                )
            }
        }
    }
}

#Preview {
    CanvasScreen()
}
