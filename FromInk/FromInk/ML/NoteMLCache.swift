import Foundation

/// A persisted cache entry for a single note's ML inference output.
struct NoteMLCache: Codable {
    /// SHA256 of the normalized OCR text that produced this output.
    /// Used to detect staleness cheaply without re-running OCR.
    let ocrHash: String
    /// The normalized OCR text stored alongside so we can compute edit
    /// distance for delta inference without re-OCRing.
    let normalizedOCR: String
    /// Foundation Models summary of the note.
    var summary: String
    /// Extracted tasks, with stable IDs so completion state survives re-runs.
    var tasks: [InkTask]
    let createdAt: Date
    /// Updated on every cache hit (even below-threshold reads) for display.
    var updatedAt: Date
}
