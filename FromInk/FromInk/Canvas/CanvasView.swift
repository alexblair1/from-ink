import SwiftUI
import PencilKit
import os

private let canvasLog = Logger(subsystem: "com.fromink.app", category: "Canvas")

/// Writes a corrupt `PKDrawing` blob to
/// `Application Support/CorruptDrawings/{pageID}-{timestamp}.pkdata` so
/// the original bytes survive even when the next save overwrites
/// `NotePage.drawingData` with an empty PKDrawing. The corrupt blobs
/// are deliberately leaked here (no cleanup) — they're rare and a
/// human investigator running into one will want every byte intact.
private func preserveCorruptDrawingBlob(_ data: Data, pageID: UUID) {
    do {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("CorruptDrawings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let url = dir.appendingPathComponent("\(pageID.uuidString)-\(stamp).pkdata")
        try data.write(to: url, options: .atomic)
        canvasLog.fault("Preserved corrupt PKDrawing blob at \(url.path, privacy: .public)")
    } catch {
        canvasLog.fault("Failed to preserve corrupt PKDrawing blob: \(error.localizedDescription)")
    }
}

/// Bridge exposing the `CanvasView.Coordinator`'s persistence inputs to
/// the parent SwiftUI view tree. `CanvasScreen` owns one per page and
/// uses it to capture-and-save from `.onDisappear` (page swipe, notebook
/// close) and scenePhase background.
///
/// **Race-free design.** Holds a weak ref to the Coordinator so the
/// bridge never extends the canvas's lifetime. `snapshotForFlush()`
/// reads the current `PKDrawing` (a value type) and `NotebookClient`
/// SYNCHRONOUSLY in the caller's runloop tick — the parent can then
/// `await persist(snapshot)` in an unstructured Task without worrying
/// about Coordinator/PKCanvasView deallocation racing the save.
@MainActor
final class CanvasViewBridge {
    private weak var coordinator: CanvasView.Coordinator?

    init() {}

    func attach(coordinator: CanvasView.Coordinator, canvas: PKCanvasView) {
        self.coordinator = coordinator
        coordinator.canvas = canvas
    }

    /// Drives the live `PKCanvasView`'s `undoManager` directly. PencilKit
    /// owns the responder-chain manager that tracks stroke deltas; reaching
    /// for SwiftUI's `@Environment(\.undoManager)` doesn't reliably hit
    /// the same manager from a wiring view above the canvas.
    func undo() {
        coordinator?.canvas?.undoManager?.undo()
    }

    func redo() {
        coordinator?.canvas?.undoManager?.redo()
    }

    /// Synchronously captures everything needed to persist the current
    /// drawing. Returns nil if the Coordinator/canvas/client is gone or
    /// the drawing hasn't changed since the last save. Caller awaits
    /// `CanvasViewBridge.persist(snapshot)` to actually write.
    func snapshotForFlush() -> FlushSnapshot? {
        guard let coordinator,
              let canvas = coordinator.canvas,
              let client = coordinator.notebookClient
        else { return nil }
        let drawing = canvas.drawing   // value-type capture
        let count = drawing.strokes.count
        // Skip if nothing has changed since the last save AND there's
        // nothing to save (count == 0 on a fresh empty page).
        if count == coordinator.lastSavedStrokeCount && count == 0 {
            return nil
        }
        coordinator.lastSavedStrokeCount = count
        return FlushSnapshot(
            pageID: coordinator.pageID,
            drawing: drawing,
            client: client
        )
    }

    /// Persists a flush snapshot. Encode + thumbnail + write run on a
    /// background Task; the snapshot owns its values so the canvas and
    /// coordinator can be deallocated mid-save without consequence.
    static func persist(_ snapshot: FlushSnapshot) async {
        let data = snapshot.drawing.dataRepresentation()
        let thumbnail = await ThumbnailRenderer.render(drawing: snapshot.drawing)
        do {
            try await snapshot.client.saveDrawing(snapshot.pageID, data, thumbnail)
        } catch {
            canvasLog.error("flush saveDrawing failed for page \(snapshot.pageID.uuidString, privacy: .public): \(error.localizedDescription)")
        }
    }

    struct FlushSnapshot: Sendable {
        let pageID: UUID
        let drawing: PKDrawing
        let client: NotebookClient
    }
}

struct CanvasView: UIViewRepresentable {
    @Binding var tool: CanvasTool
    var penSettings: PenSettings = .default
    var template: CanvasTemplate = .none
    /// Fixed page height in points — device-independent so every iPad sees the same writing surface.
    var pageHeight: CGFloat = CanvasView.standardPageHeight
    /// Persisted page identity. Drives the persistence path:
    /// `notebookClient.saveDrawing(pageID, ...)` fires on lifecycle events
    /// (page swipe, notebook close, app background) and on a stroke-count
    /// safety checkpoint — NOT on every stroke. Defaults to a fresh UUID
    /// for legacy/preview callers that aren't backed by a real page yet.
    var pageID: UUID = UUID()
    /// Initial ink loaded from `NotePage.drawingData`. Applied to the `PKCanvasView`
    /// once during `makeUIView` BEFORE the delegate is attached, so the load itself
    /// doesn't kick off any save. `nil` = brand-new page.
    var initialDrawingData: Data? = nil
    /// Persistence client. The Coordinator captures this for `flush()` —
    /// `PKDrawing` never crosses the dependency surface (the Coordinator
    /// does `dataRepresentation()` before calling).
    var notebookClient: NotebookClient? = nil
    /// Bridge object the Coordinator populates with its `flush` closure on
    /// construction. Parents (CanvasScreen) call `bridge.flush()` from
    /// lifecycle hooks (`onDisappear`, scenePhase change) to persist the
    /// current drawing without per-stroke writes. Required for save-on-
    /// lifecycle semantics; if omitted, only stroke-count safety saves fire.
    var bridge: CanvasViewBridge? = nil
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
    /// True when the active tool is the branded region tool (`.region`),
    /// false for the bare iOS lasso (`.lasso`) or any non-lasso tool.
    /// Captured by the Coordinator at lasso-BEGIN time and used as the
    /// gate for firing `onLassoReady`. Snapshotting at begin (not end)
    /// makes the toolbar-pop race irrelevant — by the time the user
    /// finishes drawing the lasso the toolbar may have already popped
    /// `.region` off `toolStack`, but our decision was already made.
    var wantsBrandedLasso: Bool = false
    var onScrollOffsetChanged: (CGPoint) -> Void = { _ in }
    var onScrolledAwayFromBottom: () -> Void = {}
    /// Set to scroll the canvas to a content offset. Resets to nil after scrolling.
    var scrollTo: Binding<CGPoint?> = .constant(nil)

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
        // itself doesn't trigger `canvasViewDrawingDidChange`.
        // If `initialDrawingData` is nil here (the common case — the
        // async fetch from `NotePage.drawingData` hasn't completed when
        // SwiftUI first renders the view), `updateUIView` re-attempts
        // the load when the binding flips to non-nil. See `applyInitial
        // DrawingIfNeeded` below.
        applyInitialDrawingIfNeeded(canvas: canvas, coordinator: context.coordinator)
        canvas.delegate = context.coordinator
        context.coordinator.pageID = pageID
        context.coordinator.notebookClient = notebookClient
        // Save-on-lifecycle: parents call `bridge.flush()` from `.onDisappear`
        // and scenePhase background. The bridge holds a weak ref to the
        // coordinator's `flush` closure so the coordinator owns its own
        // lifetime.
        bridge?.attach(coordinator: context.coordinator, canvas: canvas)
        context.coordinator.currentTool = tool
        context.coordinator.currentPenSettings = penSettings
        context.coordinator.onTwoFingerHoldBegan = onTwoFingerHoldBegan
        context.coordinator.onTwoFingerHoldEnded = onTwoFingerHoldEnded
        context.coordinator.onLassoReady = onLassoReady
        context.coordinator.onScrollOffsetChanged = onScrollOffsetChanged
        context.coordinator.onScrolledNearBottom = onScrolledNearBottom
        context.coordinator.onScrolledAwayFromBottom = onScrolledAwayFromBottom
        context.coordinator.wantsBrandedLasso = wantsBrandedLasso

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
        lassoPan.isEnabled = tool.producesLassoSelection
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
            context.coordinator.lassoPanRecognizer?.isEnabled = tool.producesLassoSelection
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
        context.coordinator.wantsBrandedLasso = wantsBrandedLasso
        // Sync persistence inputs in case pageID or client changed
        // (TabView reuse can rebind these without reinstantiating).
        context.coordinator.pageID = pageID
        context.coordinator.notebookClient = notebookClient
        // Apply persisted drawing once the async fetch resolves. The
        // first render typically has `initialDrawingData = nil`; this
        // catches the subsequent re-render with the loaded bytes.
        applyInitialDrawingIfNeeded(canvas: canvas, coordinator: context.coordinator)
    }

    /// Applies `initialDrawingData` to the canvas exactly once per
    /// coordinator lifetime, guarded by:
    /// - data is non-nil and non-empty
    /// - `didLoadInitialDrawing` is false (no previous successful load)
    /// - canvas has zero strokes (don't clobber user input that landed
    ///   before the fetch resolved)
    ///
    /// On decode failure: log a fault and write the corrupt bytes to a
    /// sidecar file under Application Support/CorruptDrawings so the
    /// next save can't permanently lose the original blob.
    private func applyInitialDrawingIfNeeded(canvas: PKCanvasView, coordinator: Coordinator) {
        guard !coordinator.didLoadInitialDrawing,
              let data = initialDrawingData,
              !data.isEmpty,
              canvas.drawing.strokes.isEmpty
        else { return }
        do {
            canvas.drawing = try PKDrawing(data: data)
            coordinator.didLoadInitialDrawing = true
            // Seed the safety-checkpoint baseline so the load itself
            // isn't counted as 50 new strokes the next time the user
            // draws.
            coordinator.lastSavedStrokeCount = canvas.drawing.strokes.count
        } catch {
            canvasLog.fault("PKDrawing(data:) decode FAILED for page \(pageID.uuidString, privacy: .public); preserving corrupt blob to sidecar: \(error.localizedDescription)")
            preserveCorruptDrawingBlob(data, pageID: pageID)
            // Mark "loaded" so we don't loop on the corrupt blob each
            // update. The sidecar holds the original bytes; the next
            // save overwrites `drawingData` with fresh ink.
            coordinator.didLoadInitialDrawing = true
        }
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
        /// Mirror of `CanvasView.wantsBrandedLasso`. Read at lasso-BEGIN
        /// time and snapshotted into `awaitingLassoSelection` so the
        /// branded-vs-bare decision survives toolbar-state changes
        /// (twoFingerHoldEnded popping `.region` off the stack mid-draw).
        var wantsBrandedLasso: Bool = false
        weak var templateLayer: PageTemplateLayer?
        weak var lassoPanRecognizer: UIPanGestureRecognizer?

        // Drawing persistence — owned by the Coordinator per CLAUDE.md
        // "Canvas + TCA boundary": never route stroke events through TCA.
        // Save-on-lifecycle: parents call `flush()` from `.onDisappear` and
        // scenePhase background; safety checkpoint fires every N strokes.
        var pageID: UUID = UUID()
        var notebookClient: NotebookClient?
        weak var canvas: PKCanvasView?

        /// Stroke count at last persisted save. `safetySaveStrokeInterval`
        /// strokes since this checkpoint triggers a non-blocking save.
        var lastSavedStrokeCount: Int = 0
        /// True once the persisted `initialDrawingData` blob has been
        /// applied to the canvas (or once a corrupt blob has been
        /// quarantined). Prevents the load from racing with user input —
        /// `updateUIView` only re-applies when this is false AND the
        /// canvas has zero strokes.
        var didLoadInitialDrawing: Bool = false
        /// Every Nth stroke triggers a background save so a heavy editing
        /// session has bounded crash-loss exposure.
        private static let safetySaveStrokeInterval = 50

        private var isNearBottom = false

        // Apple Pencil double-tap. iOS 17.5 split this into typed
        // tap / squeeze callbacks; the legacy `pencilInteractionDidTap`
        // only fires when the user's preferred tap action is set to
        // "ignore", which is why double-tap was missing for users with
        // any other system pref. The modern callback fires regardless
        // of preference.
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveTap tap: UIPencilInteraction.Tap
        ) {
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
            guard currentTool.producesLassoSelection else {
                print("[Lasso] pan fired but currentTool=\(currentTool) — ignoring")
                return
            }
            let p = recognizer.location(in: recognizer.view)
            // Reset on each fresh pan so consecutive lassos don't
            // accumulate a stale bounding rect from the previous
            // selection. Two-finger hold's own reset still fires at
            // gesture-begin; this covers the button-tap entry path
            // (`.region` / `.lasso` button) where no two-finger event
            // bookends the draw.
            if recognizer.state == .began {
                print("[Lasso] pan began at \(p)")
                resetLassoBounds()
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
            let count = canvasView.drawing.strokes.count
            onStrokeCountChanged(count)
            onDrawingChanged(canvasView.drawing)
            maybeSafetyCheckpoint(drawing: canvasView.drawing, strokeCount: count)
        }

        /// Fires a background save when `safetySaveStrokeInterval` strokes
        /// have accumulated since the last persisted checkpoint. Bounds
        /// crash-loss exposure during long editing sessions without
        /// per-stroke writes. The actual lifecycle saves (page swipe,
        /// notebook close, app background) go through `flush()`.
        private func maybeSafetyCheckpoint(drawing: PKDrawing, strokeCount: Int) {
            let delta = strokeCount - lastSavedStrokeCount
            guard delta >= Coordinator.safetySaveStrokeInterval else { return }
            lastSavedStrokeCount = strokeCount
            let id = pageID
            guard let client = notebookClient else { return }
            Task { @MainActor in
                let data = drawing.dataRepresentation()
                let thumbnail = await ThumbnailRenderer.render(drawing: drawing)
                do {
                    try await client.saveDrawing(id, data, thumbnail)
                } catch {
                    canvasLog.error("safety saveDrawing failed for page \(id.uuidString, privacy: .public): \(error.localizedDescription)")
                }
            }
        }

        // Lifecycle saves go through `CanvasViewBridge.snapshotForFlush()`
        // + `CanvasViewBridge.persist(_:)` — the bridge captures values
        // synchronously so the save survives Coordinator/canvas
        // deallocation. The safety checkpoint above is the only place
        // the Coordinator initiates a save directly.

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Snapshot the branded-or-bare intent at lasso-BEGIN. The
            // toolbar may pop `.region` off `toolStack` before the user
            // finishes the lasso (lift-hold-finger-first race), so the
            // decision can't be deferred to lasso-end. We only flip the
            // flag for PKLassoTool sessions — pen / marker / eraser
            // draws never trigger the branded menu so they don't need
            // to touch `awaitingLassoSelection`.
            guard canvasView.tool is PKLassoTool else { return }
            awaitingLassoSelection = wantsBrandedLasso
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
