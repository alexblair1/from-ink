import UIKit
import CoreGraphics
import Foundation

struct CanvasHeader: Identifiable {
    var id = UUID()
    /// Position of the header in canvas content coordinates — used for scroll navigation.
    var contentRect: CGRect
    /// Rendered image of the lassoed handwriting.
    var image: UIImage
    /// OCR result. nil while recognition is in progress.
    var ocrText: String?
    var createdAt: Date = .now
}
