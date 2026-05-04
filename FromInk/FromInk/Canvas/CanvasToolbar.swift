import SwiftUI

struct CanvasToolbar: View {
    @Binding var activeTool: CanvasTool
    @Binding var colorScheme: ColorScheme
    let side: ToolbarSide
    let isHandlePressed: Bool
    let undoManager: UndoManager?
    var toolSettings: [CanvasTool: PenSettings] = [:]
    var isPageReady: Bool = false
    var onAnalyze: () -> Void = {}
    var onCustomize: (CanvasTool) -> Void = { _ in }
    var onTemplate: () -> Void = {}
    var onSettings: () -> Void = {}

    @State private var boltExpanded = false
    @State private var boltVisible = false

    private let writingTools: [CanvasTool] = [
        .pen, .fountain, .pencil, .marker, .highlighter, .eraser, .lasso
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Ink-to-execution bolt — opacity fades first on exit, then height collapses
            boltZone
                .frame(height: boltExpanded ? 56 : 0)
                .opacity(boltVisible ? 1 : 0)
                .clipped()
                .onChange(of: isPageReady) { _, ready in
                    if ready {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            boltExpanded = true
                        }
                        withAnimation(.easeOut(duration: 0.2).delay(0.08)) {
                            boltVisible = true
                        }
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            boltVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                boltExpanded = false
                            }
                        }
                    }
                }

            // Writing tools
            ForEach(writingTools, id: \.self) { tool in
                toolButton(tool)
            }

            // Divider
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)

            // Actions
            actionButton(icon: "arrow.uturn.backward") { undoManager?.undo() }
            actionButton(icon: "arrow.uturn.forward") { undoManager?.redo() }
            actionButton(icon: "square.grid.3x3") { onTemplate() }

            // Appearance toggle
            actionButton(icon: colorScheme == .dark ? "moon" : "sun.max") {
                withAnimation(.linear(duration: 0.08)) {
                    colorScheme = colorScheme == .dark ? .light : .dark
                }
            }
            actionButton(icon: "gearshape") { onSettings() }
        }
        .frame(width: 48)
        .background(Color.surface)
        .overlay(alignment: side == .left ? .trailing : .leading) {
            Rectangle()
                .fill(Color.border)
                .frame(width: 1)
        }
    }

    private var dragHandle: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(isHandlePressed ? Color.ink : Color.inkSecondary.opacity(0.4))
                    .frame(width: 20, height: 2)
            }
        }
        .frame(width: 48, height: 54)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func toolButton(_ tool: CanvasTool) -> some View {
        let isActive = activeTool == tool
        Button {
            if isActive {
                onCustomize(tool)
            } else {
                withAnimation(.linear(duration: 0.08)) {
                    activeTool = tool
                }
            }
        } label: {
            Image(systemName: toolSettings[tool]?.penType.icon ?? tool.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isActive ? Color.inkOnDark : Color.inkSecondary)
                .frame(width: 48, height: 54)
                .background(isActive ? Color.ink : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var boltZone: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.bolt.opacity(0.25)).frame(height: 1)
            BoltButton(isReady: isPageReady, action: onAnalyze)
            Rectangle().fill(Color.bolt.opacity(0.25)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func actionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 48, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
