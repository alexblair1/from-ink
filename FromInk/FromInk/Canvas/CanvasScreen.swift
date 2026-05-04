import SwiftUI
import PencilKit

private struct HandleState {
    var isPressed = false
    var offset: CGFloat = 0
}

private enum ActiveSheet: Identifiable {
    case lasso
    case brief
    case link
    var id: String {
        switch self {
        case .lasso: return "lasso"
        case .brief: return "brief"
        case .link: return "link"
        }
    }
}

struct CanvasScreen: View {
    var onNearBottom: () -> Void = {}
    var onAwayFromBottom: () -> Void = {}

    @State private var activeTool: CanvasTool = .pen
    @State private var previousTool: CanvasTool = .pen
    @State private var toolSettings: [CanvasTool: PenSettings] = [:]
    @State private var customizingTool: CanvasTool? = nil
    @State private var activeTemplate: CanvasTemplate = .none
    @State private var showTemplatePanel = false
    @State private var strokeCount: Int = 0
    @State private var currentDrawing = PKDrawing()
    @AppStorage("correctHandwriting") private var correctHandwriting = true
    @State private var showSettingsPanel = false
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

    // Links
    @State private var links: [CanvasLink] = []
    @State private var pendingLinkContentRect: CGRect = .zero
    @State private var pendingLinkOCRText: String = ""
    @State private var isRecognizingLink = false
    @State private var activeLinkURL: URL? = nil

    private let pageReadyThreshold = 10

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

    private var activeSettings: PenSettings {
        toolSettings[activeTool] ?? .default
    }

    private func settingsBinding(for tool: CanvasTool) -> Binding<PenSettings> {
        Binding(
            get: { toolSettings[tool] ?? .default },
            set: { toolSettings[tool] = $0 }
        )
    }

    @State private var toolbarSide: ToolbarSide = {
        ToolbarSide(rawValue: UserDefaults.standard.string(forKey: "toolbarSide") ?? "") ?? .left
    }()
    @State private var colorScheme: ColorScheme = .light
    @State private var toolbarAnchorX: CGFloat = 0
    @GestureState private var handleState = HandleState()
    @Environment(\.undoManager) private var undoManager

    var toolbarX: CGFloat { toolbarAnchorX + handleState.offset }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.canvas.ignoresSafeArea()
                    #if DEBUG
                    .sheet(isPresented: $showDebugSheet) { ExtractionDebugSheet() }
                    #endif

                CanvasView(
                    tool: $activeTool,
                    penSettings: activeSettings,
                    template: activeTemplate,
                    onTwoFingerHoldBegan: {
                        previousTool = activeTool
                        activeTool = .lasso
                    },
                    onTwoFingerHoldEnded: {
                        activeTool = previousTool
                    },
                    onPencilDoubleTap: {
                        withAnimation(.linear(duration: 0.08)) {
                            if activeTool == .eraser {
                                activeTool = previousTool
                            } else {
                                previousTool = activeTool
                                activeTool = .eraser
                            }
                        }
                    },
                    onStrokeCountChanged: { strokeCount = $0 },
                    onDrawingChanged: { currentDrawing = $0 },
                    onScrolledNearBottom: onNearBottom,
                    onLassoReady: { image, viewRect, contentRect in
                        lassoMenuImage = image
                        lassoMenuRect = viewRect
                        lassoContentRect = contentRect
                        showLassoMenu = true
                    },
                    onScrollOffsetChanged: { scrollOffset = $0 },
                    onScrolledAwayFromBottom: onAwayFromBottom
                )
                .ignoresSafeArea()

                // Link indicators — positioned in view space using scroll offset
                ForEach(links) { link in
                    let viewX = link.contentRect.midX - scrollOffset.x
                    let viewY = link.contentRect.midY - scrollOffset.y
                    LinkIndicator(link: link) {
                        activeLinkURL = link.url
                    }
                    .position(x: viewX, y: viewY)
                }

                CanvasToolbar(
                    activeTool: $activeTool,
                    colorScheme: $colorScheme,
                    side: toolbarSide,
                    isHandlePressed: handleState.isPressed,
                    undoManager: undoManager,
                    toolSettings: toolSettings,
                    isPageReady: strokeCount >= pageReadyThreshold,
                    onAnalyze: {
                        briefTasks = []
                        briefSummary = ""
                        briefOpenQuestion = nil
                        isAnalyzing = true
                        activeSheet = .brief
                        Task {
                            defer { isAnalyzing = false }
                            let result = await InkTaskExtractor.extract(drawing: currentDrawing, scope: .page)
                            briefSummary = result.summary
                            briefTasks = result.tasks
                            briefOpenQuestion = result.openQuestion
                        }
                    },
                    onCustomize: { tool in
                        withAnimation(.linear(duration: 0.08)) {
                            customizingTool = customizingTool == tool ? nil : tool
                            showTemplatePanel = false
                        }
                    },
                    onTemplate: {
                        withAnimation(.linear(duration: 0.08)) {
                            showTemplatePanel.toggle()
                            customizingTool = nil
                            showSettingsPanel = false
                        }
                    },
                    onSettings: {
                        withAnimation(.linear(duration: 0.08)) {
                            showSettingsPanel.toggle()
                            customizingTool = nil
                            showTemplatePanel = false
                        }
                    },
                    onDebug: {
                        #if DEBUG
                        showDebugSheet = true
                        #endif
                    }
                )
                .offset(x: toolbarX)
                .shadow(
                    color: handleState.isPressed ? .black.opacity(0.16) : .clear,
                    radius: handleState.isPressed ? 18 : 0,
                    x: handleState.isPressed ? (toolbarSide == .left ? 8 : -8) : 0,
                    y: 0
                )
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .updating($handleState) { value, state, _ in
                            guard value.startLocation.y <= 54 else { return }
                            state.isPressed = true
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            state.offset = value.translation.width
                        }
                        .onEnded { value in
                            guard value.startLocation.y <= 54 else { return }
                            let dx = value.translation.width
                            guard abs(dx) > abs(value.translation.height) else { return }
                            let target: ToolbarSide = abs(dx) > 40
                                ? (dx > 0 ? .right : .left)
                                : toolbarSide
                            let finalX: CGFloat = target == .left ? 0 : geo.size.width - 48
                            toolbarAnchorX += dx
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                toolbarAnchorX = finalX
                                toolbarSide = target
                            }
                            UserDefaults.standard.set(target.rawValue, forKey: "toolbarSide")
                        }
                )

                if showTemplatePanel {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.linear(duration: 0.08)) { showTemplatePanel = false }
                        }

                    TemplatePickerPanel(template: $activeTemplate, onDismiss: {
                        withAnimation(.linear(duration: 0.08)) { showTemplatePanel = false }
                    })
                    .position(
                        x: toolbarSide == .left
                            ? toolbarX + 48 + 8 + 110
                            : toolbarX - 8 - 110,
                        y: geo.size.height / 2
                    )
                }

                if showSettingsPanel {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.linear(duration: 0.08)) { showSettingsPanel = false }
                        }

                    CanvasSettingsPanel(onDismiss: {
                        withAnimation(.linear(duration: 0.08)) { showSettingsPanel = false }
                    })
                    .position(
                        x: toolbarSide == .left
                            ? toolbarX + 48 + 8 + 140
                            : toolbarX - 8 - 140,
                        y: geo.size.height - 120
                    )
                }

                if let activePanelTool = customizingTool {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.linear(duration: 0.08)) {
                                customizingTool = nil
                            }
                        }

                    PenCustomizationPanel(
                        tool: activePanelTool,
                        settings: settingsBinding(for: activePanelTool),
                        onDismiss: {
                            withAnimation(.linear(duration: 0.08)) { customizingTool = nil }
                        }
                    )
                    .position(
                        x: toolbarSide == .left
                            ? toolbarX + 48 + 8 + 130
                            : toolbarX - 8 - 130,
                        y: geo.size.height / 2
                    )
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
            }
            .onAppear {
                toolbarAnchorX = toolbarSide == .left ? 0 : geo.size.width - 48
            }
            .onChange(of: geo.size.width) { _, newWidth in
                toolbarAnchorX = toolbarSide == .left ? 0 : newWidth - 48
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: Binding(
            get: { activeLinkURL != nil },
            set: { if !$0 { activeLinkURL = nil } }
        )) {
            if let url = activeLinkURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .lasso:
                LassoActionSheet(
                    isLoading: isRecognizing,
                    task: lassoTask ?? InkTask(title: ""),
                    onDismiss: { activeSheet = nil },
                    onSend: { _ in activeSheet = nil }
                )
            case .brief:
                BriefSheet(
                    isLoading: isAnalyzing,
                    summary: briefSummary,
                    tasks: $briefTasks,
                    openQuestion: briefOpenQuestion,
                    onDismiss: { activeSheet = nil },
                    onSendAll: { activeSheet = nil }
                )
            case .link:
                LinkInputSheet(
                    isLoading: isRecognizingLink,
                    recognizedText: pendingLinkOCRText,
                    onConfirm: { url in
                        let link = CanvasLink(
                            contentRect: pendingLinkContentRect,
                            recognizedText: pendingLinkOCRText,
                            url: url
                        )
                        links.append(link)
                        activeSheet = nil
                    },
                    onDismiss: { activeSheet = nil }
                )
            }
        }
    }
}

#Preview {
    CanvasScreen()
}
