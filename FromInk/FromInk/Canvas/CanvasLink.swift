import Foundation
import CoreGraphics

struct CanvasLink: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Bounding rect of the linked region in canvas content coordinates (not scroll-adjusted).
    var contentRect: CGRect
    /// OCR-recognized text for the linked region — shown in the link sheet and used as a label.
    var recognizedText: String
    /// The URL this ink region links to.
    var url: URL
}
