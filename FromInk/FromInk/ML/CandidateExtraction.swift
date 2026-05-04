import Foundation

/// Stage 1 deterministic extraction result.
/// Produced using NaturalLanguage + NSDataDetector — no Foundation Models required.
struct CandidateExtraction {

    struct TaskCandidate {
        /// The raw sentence from OCR text.
        var sentence: String
        /// Dates detected within this sentence by NSDataDetector.
        var detectedDates: [Date]
        /// Person names detected within this sentence by NLTagger(.nameType).
        var detectedPersons: [String]
        /// Organization names detected within this sentence.
        var detectedOrganizations: [String]
        /// Place names detected within this sentence.
        var detectedPlaces: [String]
    }

    /// Sentences that look like imperative task statements.
    var candidates: [TaskCandidate]
    /// All dates found anywhere in the full text.
    var allDates: [Date]
    /// All person names found anywhere in the full text.
    var allPersons: [String]
    /// The raw OCR text this was extracted from.
    var rawText: String

    var isEmpty: Bool { candidates.isEmpty }
}
