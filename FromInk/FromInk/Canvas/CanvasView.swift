import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var tool: CanvasTool
    var penSettings: PenSettings = .default
    var onTwoFingerHoldBegan: () -> Void = {}
    var onTwoFingerHoldEnded: () -> Void = {}
    var onPencilDoubleTap: () -> Void = {}
    var onStrokeCountChanged: (Int) -> Void = { _ in }
    var onDrawingChanged: (PKDrawing) -> Void = { _ in }
    var onLassoCompleted: (UIImage) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.tool = tool.pkTool(settings: penSettings)
        canvas.delegate = context.coordinator
        context.coordinator.currentTool = tool
        context.coordinator.currentPenSettings = penSettings
        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoCompleted = onLassoCompleted

        // Two-finger hold → lasso mode
        let twoFingerHold = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerHold(_:))
        )
        twoFingerHold.numberOfTouchesRequired = 2
        twoFingerHold.minimumPressDuration = 0.15
        twoFingerHold.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        twoFingerHold.cancelsTouchesInView = false
        twoFingerHold.delaysTouchesBegan = false
        twoFingerHold.delaysTouchesEnded = false
        twoFingerHold.delegate = context.coordinator
        canvas.addGestureRecognizer(twoFingerHold)

        // Pencil pan — tracks bounding rect of the lasso stroke
        let lassoPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.trackLassoBounds(_:))
        )
        lassoPan.allowedTouchTypes = [UITouch.TouchType.pencil.rawValue as NSNumber]
        lassoPan.cancelsTouchesInView = false
        lassoPan.delaysTouchesBegan = false
        lassoPan.delaysTouchesEnded = false
        lassoPan.delegate = context.coordinator
        canvas.addGestureRecognizer(lassoPan)

        // Apple Pencil double-tap
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if context.coordinator.currentTool != tool || context.coordinator.currentPenSettings != penSettings {
            canvas.tool = tool.pkTool(settings: penSettings)
            context.coordinator.currentTool = tool
            context.coordinator.currentPenSettings = penSettings
        }
        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoCompleted = onLassoCompleted
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        context.coordinator.onStrokeCountChanged = onStrokeCountChanged
        context.coordinator.onDrawingChanged = onDrawingChanged
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var currentTool: CanvasTool = .pen
        var currentPenSettings: PenSettings = .default
        var onTwoFingerHoldBegan: () -> Void = {}
        var onTwoFingerHoldEnded: () -> Void = {}
        var onLassoCompleted: (UIImage) -> Void = { _ in }
        var onPencilDoubleTap: () -> Void = {}
        var onStrokeCountChanged: (Int) -> Void = { _ in }
        var onDrawingChanged: (PKDrawing) -> Void = { _ in }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap()
        }

        // Bounding rect accumulated from pencil touch points during lasso
        private var lassoMinX: CGFloat = .infinity
        private var lassoMinY: CGFloat = .infinity
        private var lassoMaxX: CGFloat = -.infinity
        private var lassoMaxY: CGFloat = -.infinity
        private var hasLassoBounds = false

        var awaitingLassoSelection = false

        // MARK: - Two-finger hold

        @objc func handleTwoFingerHold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                print("[Lasso] two-finger hold began — awaiting lasso selection")
                awaitingLassoSelection = true
                resetLassoBounds()
                onTwoFingerHoldBegan()
            case .ended, .cancelled, .failed:
                print("[Lasso] two-finger hold ended/cancelled")
                onTwoFingerHoldEnded()
            default:
                break
            }
        }

        // MARK: - Lasso bounds tracking

        @objc func trackLassoBounds(_ recognizer: UIPanGestureRecognizer) {
            guard currentTool == .lasso else {
                print("[Lasso] pan fired but currentTool=\(currentTool) — ignoring")
                return
            }
            let p = recognizer.location(in: recognizer.view)
            if recognizer.state == .began {
                print("[Lasso] pan began at \(p)")
            }
            lassoMinX = min(lassoMinX, p.x)
            lassoMinY = min(lassoMinY, p.y)
            lassoMaxX = max(lassoMaxX, p.x)
            lassoMaxY = max(lassoMaxY, p.y)
            hasLassoBounds = true
        }

        private func resetLassoBounds() {
            lassoMinX = .infinity
            lassoMinY = .infinity
            lassoMaxX = -.infinity
            lassoMaxY = -.infinity
            hasLassoBounds = false
        }

        private var lassoBounds: CGRect? {
            guard hasLassoBounds,
                  lassoMaxX > lassoMinX,
                  lassoMaxY > lassoMinY else { return nil }
            return CGRect(x: lassoMinX, y: lassoMinY,
                          width: lassoMaxX - lassoMinX,
                          height: lassoMaxY - lassoMinY)
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onStrokeCountChanged(canvasView.drawing.strokes.count)
            onDrawingChanged(canvasView.drawing)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            print("[Lasso] canvasViewDidEndUsingTool — awaitingLasso=\(awaitingLassoSelection), tool=\(type(of: canvasView.tool))")
            guard awaitingLassoSelection,
                  canvasView.tool is PKLassoTool else {
                print("[Lasso] delegate guard failed — skipping")
                return
            }
            awaitingLassoSelection = false

            let drawing = canvasView.drawing
            print("[Lasso] drawing has \(drawing.strokes.count) strokes, hasLassoBounds=\(hasLassoBounds)")
            guard !drawing.strokes.isEmpty else {
                print("[Lasso] no strokes — aborting")
                return
            }

            // Use the tracked lasso bounds, falling back to all-stroke bounds
            let region: CGRect
            if let bounds = lassoBounds {
                print("[Lasso] using tracked bounds: \(bounds)")
                region = bounds.insetBy(dx: -24, dy: -24)
            } else {
                print("[Lasso] no tracked bounds — falling back to stroke union")
                region = drawing.strokes
                    .map { $0.renderBounds }
                    .reduce(CGRect.null) { $0.union($1) }
                    .insetBy(dx: -24, dy: -24)
            }

            print("[Lasso] rendering region: \(region)")
            // Render the full drawing clipped to the lasso region at 3x for OCR quality
            let image = drawing.image(from: region, scale: 3)
            print("[Lasso] image size: \(image.size), firing onLassoCompleted")
            onLassoCompleted(image)
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
