import SwiftUI

private struct HandleState {
    var isPressed = false
    var offset: CGFloat = 0
}

struct CanvasScreen: View {
    @State private var activeTool: CanvasTool = .pen
    @State private var previousTool: CanvasTool = .pen
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
                CanvasView(
                    tool: $activeTool,
                    onTwoFingerHoldBegan: {
                        previousTool = activeTool
                        activeTool = .lasso
                    },
                    onTwoFingerHoldEnded: {
                        activeTool = previousTool
                    },
                    onLassoCompleted: { image in
                        lassoRecognizedText = ""
                        isRecognizing = true
                        showLassoSheet = true
                        Task {
                            print("[Screen] onLassoCompleted — running OCR")
                            lassoRecognizedText = await LassoOCR.recognize(image: image)
                            print("[Screen] OCR done → \"\(lassoRecognizedText)\"")
                            isRecognizing = false
                        }
                    }
                )
                .ignoresSafeArea()

                CanvasToolbar(
                    activeTool: $activeTool,
                    colorScheme: $colorScheme,
                    side: toolbarSide,
                    isHandlePressed: handleState.isPressed,
                    undoManager: undoManager
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
                recognizedText: lassoRecognizedText,
                isLoading: isRecognizing,
                onDismiss: { showLassoSheet = false }
            )
        }
    }
}

#Preview {
    CanvasScreen()
}
