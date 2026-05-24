import PencilKit
import UIKit

/// Renders a `PKDrawing` into a PNG thumbnail suitable for library
/// cards (~256px wide). Runs the `PKDrawing.image(from:scale:)` call
/// on the MainActor (the call is main-isolated on iOS 17+), then
/// returns PNG `Data` that `NotebookClient.saveDrawing` stores on
/// `NotePage.thumbnailData` with `@Attribute(.externalStorage)`.
///
/// Cost on M-class iPad: ~10–30 ms per render. On slower devices
/// (iPad mini A17 Pro: ~50–100 ms). Called at the 800 ms debounce
/// boundary in `CanvasView.Coordinator`, so the worst-case cadence
/// is ~1.25 renders/sec — acceptable. If profiling shows pressure,
/// the call site can throttle thumbnails to every Nth save.
enum ThumbnailRenderer {
    /// `targetWidth` is the desired pixel width of the rendered PNG.
    /// The render scale is derived to make the drawing fit that width,
    /// clamped so degenerate empty drawings don't produce huge bitmaps.
    static func render(drawing: PKDrawing, targetWidth: CGFloat = 256) async -> Data? {
        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 1, height: 1)
            : drawing.bounds
        let renderScale = max(0.1, min(2.0, targetWidth / max(bounds.width, 1)))
        let image = await MainActor.run {
            drawing.image(from: bounds, scale: renderScale)
        }
        return image.pngData()
    }
}
