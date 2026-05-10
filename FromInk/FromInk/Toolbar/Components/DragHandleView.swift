import SwiftUI

/// Drag handle at the top of the toolbar for switching sides.
/// Component view — no TCA imports.
///
struct DragHandleView: View {
    let model: Model

    @GestureState private var isDragging = false

    var body: some View {
        VStack(spacing: model.capsuleSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(isDragging ? model.pressedColor : model.idleColor)
                    .frame(width: model.capsuleWidth, height: model.capsuleHeight)
            }
        }
        .frame(width: model.width, height: model.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onEnded { value in
                    let dx = value.translation.width
                    
                    guard
                        abs(dx) > abs(value.translation.height),
                        abs(dx) > model.sideSwitchThreshold
                    else {
                        return
                    }
                    
                    let side: ToolbarSide = dx > 0 ? .right : .left
                    model.onDragEnded(side)
                }
        )
    }
}

// MARK: - Model

extension DragHandleView {
    struct Model {
        let onDragEnded: (ToolbarSide) -> Void
        let width: CGFloat
        let height: CGFloat
        let capsuleWidth: CGFloat
        let capsuleHeight: CGFloat
        let capsuleSpacing: CGFloat
        let sideSwitchThreshold: CGFloat
        let idleColor: Color
        let pressedColor: Color
    }
}

// MARK: - Model init

extension DragHandleView.Model {
    init(
        onDragEnded: @escaping (ToolbarSide) -> Void,
        ds: DesignSystem = .standard
    ) {
        self.onDragEnded = onDragEnded
        self.width = ds.layout.toolbarWidth
        self.height = ds.layout.toolbarButtonHeight
        self.capsuleWidth = ds.layout.dragHandleCapsuleWidth
        self.capsuleHeight = ds.layout.dragHandleCapsuleHeight
        self.capsuleSpacing = ds.layout.dragHandleCapsuleSpacing
        self.sideSwitchThreshold = ds.layout.dragHandleSwitchThreshold
        self.idleColor = ds.colors.ink3
        self.pressedColor = ds.colors.ink
    }
}
