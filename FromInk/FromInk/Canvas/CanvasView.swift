import SwiftUI
import PencilKit
import os

private let canvasLog = Logger(subsystem: "com.fromink.app", category: "Canvas")

struct CanvasView: UIViewRepresentable {
    @Binding var tool: CanvasTool
    var penSettings: PenSettings = .default
    var template: CanvasTemplate = .none
    /// Fixed page height in points — device-independent so every iPad sees the same writing surface.
    var pageHeight: CGFloat = CanvasView.standardPageHeight
    /// Persisted page identity. Drives the persistence path: `notebookClient.saveDrawing(pageID, ...)`
    /// fires 800 ms after the last stroke. Defaults to a fresh UUID for legacy/preview
    /// callers that aren't backed by a real page yet.
    var pageID: UUID = UUID()
    /// Initial ink loaded from `NotePage.drawingData`. Applied to the `PKCanvasView`
    /// once during `makeUIView` BEFORE the delegate is attached, so the load itself
    /// doesn't kick off the debounce-save loop. `nil` = brand-new page.
    var initialDrawingData: Data? = nil
    /// Persistence client. The Coordinator captures this for the debounced
    /// `saveDrawing` call — `PKDrawing` itself never crosses the dependency
    /// surface (the Coordinator does `dataRepresentation()` before calling).
    var notebookClient: NotebookClient? = nil
    var onTwoFingerHoldBegan: () -> Void = {}
    var onTwoFingerHoldEnded: () -> Void = {}
    var onPencilDoubleTap: () -> Void = {}
    var onStrokeCountChanged: (Int) -> Void = { _ in }
    var onDrawingChanged: (PKDrawing) -> Void = { _ in }
    var onScrolledNearBottom: () -> Void = {}
    /// Called when a lasso stroke completes.
    /// - Parameters:
    ///   - image: Rendered image of the selected region (scale 4).
    ///   - viewRect: Selected content bounds in view coordinates (scroll-adjusted) — use for UI positioning.
    ///   - contentRect: Selected content bounds in canvas content coordinates — use for persistence.
    var onLassoReady: (UIImage, CGRect, CGRect) -> Void = { _, _, _ in }
    var onScrollOffsetChanged: (CGPoint) -> Void = { _ in }
    var onScrolledAwayFromBottom: () -> Void = {}
    /// Set to scroll the canvas to a content offset. Resets to nil after scrolling.
    var scrollTo: Binding<CGPoint?> = .constant(nil)
    /// Width of the finger-only long press zone for the header panel.
    var headerStripWidth: CGFloat = 264
    /// True when the strip is on the right edge (toolbar is on the left).
    var headerStripOnRight: Bool = true
    var onHeaderPanelRequested: () -> Void = {}

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
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false

        // Load persisted ink BEFORE attaching the delegate so the load
        // itself doesn't trigger `canvasViewDrawingDidChange` → save loop.
        // If the stored data is corrupt (cross-iOS-version drift), log
        // and fall back to an empty page — the next save overwrites.
        if let data = initialDrawingData, !data.isEmpty {
            do {
                canvas.drawing = try PKDrawing(data: data)
            } catch {
                canvasLog.error("PKDrawing(data:) failed for page \(pageID.uuidString, privacy: .public): \(error.localizedDescription)")
            }
        }
        canvas.delegate = context.coordinator
        context.coordinator.pageID = pageID
        context.coordinator.notebookClient = notebookClient
        context.coordinator.currentTool = tool
        context.coordinator.currentPenSettings = penSettings
        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoReady = onLassoReady
        context.coordinator.onScrollOffsetChanged = onScrollOffsetChanged
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

        // Header strip — finger-only inward swipe from the edge opposite the toolbar
        let headerSwipe = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHeaderSwipe(_:))
        )
        headerSwipe.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        headerSwipe.maximumNumberOfTouches = 1
        headerSwipe.cancelsTouchesInView = false
        headerSwipe.delaysTouchesBegan = false
        headerSwipe.delaysTouchesEnded = false
        headerSwipe.delegate = context.coordinator
        canvas.addGestureRecognizer(headerSwipe)
        context.coordinator.headerSwipeRecognizer = headerSwipe
        context.coordinator.headerStripWidth = headerStripWidth
        context.coordinator.headerStripOnRight = headerStripOnRight
        context.coordinator.onHeaderPanelRequested = onHeaderPanelRequested

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

        // Programmatic scroll — consume target then reset to nil
        if let target = scrollTo.wrappedValue {
            canvas.setContentOffset(target, animated: true)
            DispatchQueue.main.async { scrollTo.wrappedValue = nil }
        }

        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoReady = onLassoReady
        context.coordinator.onScrollOffsetChanged = onScrollOffsetChanged
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        context.coordinator.onStrokeCountChanged = onStrokeCountChanged
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onScrolledNearBottom = onScrolledNearBottom
        context.coordinator.onScrolledAwayFromBottom = onScrolledAwayFromBottom
        context.coordinator.headerStripWidth = headerStripWidth
        context.coordinator.headerStripOnRight = headerStripOnRight
        context.coordinator.onHeaderPanelRequested = onHeaderPanelRequested
        // Sync persistence inputs in case pageID or client changed
        // (TabView reuse can rebind these without reinstantiating).
        context.coordinator.pageID = pageID
        context.coordinator.notebookClient = notebookClient
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var currentTool: CanvasTool = .pen
        var currentPenSettings: PenSettings = .default
        var onTwoFingerHoldBegan: () -> Void = {}
        var onTwoFingerHoldEnded: () -> Void = {}
        var onLassoReady: (UIImage, CGRect, CGRect) -> Void = { _, _, _ in }
        var onScrollOffsetChanged: (CGPoint) -> Void = { _ in }
        var onPencilDoubleTap: () -> Void = {}
        var onStrokeCountChanged: (Int) -> Void = { _ in }
        var onDrawingChanged: (PKDrawing) -> Void = { _ in }
        var onScrolledNearBottom: () -> Void = {}
        var onScrolledAwayFromBottom: () -> Void = {}
        var onHeaderPanelRequested: () -> Void = {}
        var headerStripWidth: CGFloat = 264
        var headerStripOnRight: Bool = true
        weak var templateLayer: PageTemplateLayer?
        weak var lassoPanRecognizer: UIPanGestureRecognizer?
        weak var headerSwipeRecognizer: UIPanGestureRecognizer?
        private var headerSwipeFired = false

        // Drawing persistence — owned by the Coordinator per CLAUDE.md
        // "Canvas + TCA boundary": never route 60Hz stroke events through
        // TCA. The 800ms debounce matches the OCR debounce in the EDD.
        var pageID: UUID = UUID()
        var notebookClient: NotebookClient?
        private var saveDebounceTask: Task<Void, Never>?

        deinit { saveDebounceTask?.cancel() }

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

        // MARK: - Header strip

        @objc func handleHeaderSwipe(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began:
                headerSwipeFired = false
            case .changed:
                guard !headerSwipeFired else { return }
                let translation = recognizer.translation(in: view)
                let velocity = recognizer.velocity(in: view)
                // Must be primarily horizontal
                guard abs(translation.x) > abs(translation.y) else { return }
                // Inward direction: left when strip is on right, right when strip is on left
                let inwardTranslation = headerStripOnRight ? -translation.x : translation.x
                let inwardVelocity   = headerStripOnRight ? -velocity.x   : velocity.x
                if inwardTranslation > 30 || inwardVelocity > 400 {
                    headerSwipeFired = true
                    onHeaderPanelRequested()
                }
            case .ended, .cancelled, .failed:
                headerSwipeFired = false
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
            onScrollOffsetChanged(scrollView.contentOffset)

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
            scheduleSave(drawing: canvasView.drawing)
        }

        /// 800 ms debounced persist. Cancels any in-flight save before
        /// queueing a new one, so a burst of stroke changes (60 Hz under
        /// active pencil) collapses to a single write per idle window.
        /// Persistence path: encode → thumbnail → `NotebookClient.saveDrawing`.
        private func scheduleSave(drawing: PKDrawing) {
            guard let client = notebookClient else { return }
            let id = pageID
            saveDebounceTask?.cancel()
            saveDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                let data = drawing.dataRepresentation()
                let thumbnail = await ThumbnailRenderer.render(drawing: drawing)
                do {
                    try await client.saveDrawing(id, data, thumbnail)
                } catch {
                    canvasLog.error("saveDrawing failed for page \(id.uuidString, privacy: .public): \(error.localizedDescription)")
                }
            }
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
            print("[Lasso] image size: \(image.size), firing onLassoReady")

            // Content bounds: union of renderBounds of strokes inside the lasso region.
            // This is tighter than `region` (which pads the lasso path itself) and gives
            // a highlight that matches the actual ink rather than the drawn selection loop.
            let selectedStrokes = drawing.strokes.filter { region.intersects($0.renderBounds) }
            let contentBounds = selectedStrokes.isEmpty ? region :
                selectedStrokes.map { $0.renderBounds }.reduce(CGRect.null) { $0.union($1) }

            // Convert content bounds from content space → view space (accounts for scroll).
            let viewRect = CGRect(
                x: contentBounds.minX - canvasView.contentOffset.x,
                y: contentBounds.minY - canvasView.contentOffset.y,
                width: contentBounds.width,
                height: contentBounds.height
            )
            onLassoReady(image, viewRect, contentBounds)
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === headerSwipeRecognizer,
                  let view = gestureRecognizer.view else { return true }
            let x = gestureRecognizer.location(in: view).x
            return headerStripOnRight
                ? x >= view.bounds.width - headerStripWidth
                : x <= headerStripWidth
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
