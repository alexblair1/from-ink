import SwiftUI
import PencilKit

private struct HandleState {
    var isPressed = false
    var offset: CGFloat = 0
}

struct CanvasScreen: View {
    @State private var activeTool: CanvasTool = .pen
    @State private var previousTool: CanvasTool = .pen
    @State private var toolSettings: [CanvasTool: PenSettings] = [:]
    @State private var customizingTool: CanvasTool? = nil
    @State private var activeTemplate: CanvasTemplate = .none
    @State private var showTemplatePanel = false
    @State private var strokeCount: Int = 0
    @State private var currentDrawing = PKDrawing()

    // Brief sheet
    @State private var showBriefSheet = false
    @State private var isAnalyzing = false
    @State private var briefSummary: String = ""
    @State private var briefTasks: [ExtractedTask] = []
    @State private var briefOpenQuestion: String? = nil

    private let pageReadyThreshold = 10

    private var activeSettings: PenSettings {
        toolSettings[activeTool] ?? .default
    }

    private func settingsBinding(for tool: CanvasTool) -> Binding<PenSettings> {
        Binding(
            get: { toolSettings[tool] ?? .default },
            set: { toolSettings[tool] = $0 }
        )
    }
    @State private var lassoRecognizedText: String = ""
    @State private var showLassoSheet = false
    @State private var isRecognizing = false
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
                TemplateView(template: activeTemplate)
                    .ignoresSafeArea()

                CanvasView(
                    tool: $activeTool,
                    penSettings: activeSettings,
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
                    onLassoCompleted: { image in
                        lassoRecognizedText = ""
                        isRecognizing = true
                        showLassoSheet = true
                        Task {
                            defer { isRecognizing = false }
                            print("[Screen] onLassoCompleted — running OCR")
                            lassoRecognizedText = await LassoOCR.recognize(image: image)
                            print("[Screen] OCR done → \"\(lassoRecognizedText)\"")
                        }
                    }
                )
                .ignoresSafeArea()

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
                        showBriefSheet = true
                        Task {
                            defer { isAnalyzing = false }
                            let result = await PageAnalyzer.analyze(drawing: currentDrawing)
                            briefSummary = result.summary
                            briefTasks = result.tasks.map {
                                ExtractedTask(title: $0.title, detail: $0.detail)
                            }
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
                        }
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
        .sheet(isPresented: $showLassoSheet) {
            LassoActionSheet(
                isLoading: isRecognizing,
                recognizedText: lassoRecognizedText,
                onDismiss: { showLassoSheet = false },
                onSend: { _ in showLassoSheet = false }
            )
        }
        .sheet(isPresented: $showBriefSheet) {
            BriefSheet(
                isLoading: isAnalyzing,
                summary: briefSummary,
                tasks: $briefTasks,
                openQuestion: briefOpenQuestion,
                onDismiss: { showBriefSheet = false },
                onSendAll: { showBriefSheet = false }
            )
        }
    }
}

#Preview {
    CanvasScreen()
}
