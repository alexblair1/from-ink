import SwiftUI

struct CanvasToolbar: View {
    @Binding var activeTool: CanvasTool
    @Binding var colorScheme: ColorScheme
    let side: ToolbarSide
    let isHandlePressed: Bool
    let undoManager: UndoManager?

    private let writingTools: [CanvasTool] = [
        .pen, .fountain, .pencil, .marker, .highlighter, .eraser, .lasso
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

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

            // Layers placeholder (V2)
            actionButton(icon: "square.3.layers.3d") {}

            // Appearance toggle
            actionButton(icon: colorScheme == .dark ? "moon" : "sun.max") {
                withAnimation(.linear(duration: 0.08)) {
                    colorScheme = colorScheme == .dark ? .light : .dark
                }
            }
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
            withAnimation(.linear(duration: 0.08)) {
                activeTool = tool
            }
        } label: {
            Image(systemName: tool.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isActive ? Color.inkOnDark : Color.inkSecondary)
                .frame(width: 48, height: 54)
                .background(isActive ? Color.ink : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
