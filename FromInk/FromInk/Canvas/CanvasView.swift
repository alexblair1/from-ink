import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var tool: CanvasTool
    var penSettings: PenSettings = .default
    var template: CanvasTemplate = .none
    /// Fixed page height in points — device-independent so every iPad sees the same writing surface.
    var pageHeight: CGFloat = CanvasView.standardPageHeight
    var onTwoFingerHoldBegan: () -> Void = {}
    var onTwoFingerHoldEnded: () -> Void = {}
    var onPencilDoubleTap: () -> Void = {}
    var onStrokeCountChanged: (Int) -> Void = { _ in }
    var onDrawingChanged: (PKDrawing) -> Void = { _ in }
    var onScrolledNearBottom: () -> Void = {}
    var onLassoCompleted: (UIImage) -> Void = { _ in }
    var onScrolledAwayFromBottom: () -> Void = {}

    /// The fixed page height used across all devices.
    /// 3× the portrait height of the 13" iPad Pro (3 × 1366 pt) —
    /// roughly 3 screens of writing space per page.
    static let standardPageHeight: CGFloat = 4098

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.tool = tool.pkTool(settings: penSettings)
        canvas.delegate = context.coordinator
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        context.coordinator.currentTool = tool
        context.coordinator.currentPenSettings = penSettings
        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoCompleted = onLassoCompleted
        context.coordinator.onScrolledNearBottom = onScrolledNearBottom
        context.coordinator.onScrolledAwayFromBottom = onScrolledAwayFromBottom

        // Template background layer — inserted below PencilKit's drawing layer
        let templateLayer = PageTemplateLayer()
        templateLayer.template = template
        canvas.insertSubview(templateLayer, at: 0)
        context.coordinator.templateLayer = templateLayer

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
        lassoPan.isEnabled = tool == .lasso
        canvas.addGestureRecognizer(lassoPan)
        context.coordinator.lassoPanRecognizer = lassoPan

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
            context.coordinator.lassoPanRecognizer?.isEnabled = (tool == .lasso)
        }

        // Update page size — re-apply tool after contentSize change because PencilKit
        // resets canvas.tool internally when contentSize is mutated on a fresh canvas.
        let targetSize = CGSize(width: canvas.bounds.width, height: pageHeight)
        if canvas.contentSize != targetSize {
            canvas.isScrollEnabled = true
            canvas.contentSize = targetSize
            canvas.tool = tool.pkTool(settings: penSettings)
            context.coordinator.templateLayer?.frame = CGRect(origin: .zero, size: targetSize)
            context.coordinator.templateLayer?.setNeedsDisplay()
        }

        // Update template
        if context.coordinator.templateLayer?.template != template {
            context.coordinator.templateLayer?.template = template
        }

        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoCompleted = onLassoCompleted
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        context.coordinator.onStrokeCountChanged = onStrokeCountChanged
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onScrolledNearBottom = onScrolledNearBottom
        context.coordinator.onScrolledAwayFromBottom = onScrolledAwayFromBottom
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
        var onScrolledNearBottom: () -> Void = {}
        var onScrolledAwayFromBottom: () -> Void = {}
        weak var templateLayer: PageTemplateLayer?
        weak var lassoPanRecognizer: UIPanGestureRecognizer?

        private var isNearBottom = false

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

        // MARK: - UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let distanceFromBottom = scrollView.contentSize.height
                - scrollView.contentOffset.y
                - scrollView.bounds.height
            let near = distanceFromBottom < 120
            guard near != isNearBottom else { return }
            isNearBottom = near
            if near { onScrolledNearBottom() } else { onScrolledAwayFromBottom() }
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
            let image = drawing.image(from: region, scale: 4)
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
