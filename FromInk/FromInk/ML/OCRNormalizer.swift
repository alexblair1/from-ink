import CryptoKit
import Foundation

enum OCRNormalizer {

    // MARK: - Normalize

    /// Returns a canonical form of OCR text suitable for hashing and change detection.
    static func normalize(_ text: String) -> String {
        var result = text
        // Trim outer whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse internal whitespace runs to a single space
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Smart quotes → straight
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")
        // Em dash / en dash → double hyphen
        result = result.replacingOccurrences(of: "\u{2014}", with: "--")
        result = result.replacingOccurrences(of: "\u{2013}", with: "--")
        return result.lowercased()
    }

    // MARK: - Hash

    /// SHA256 hex digest of the normalized text — used as the cache key.
    static func hash(_ normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Edit distance

    /// Normalized edit distance between two strings in [0.0, 1.0].
    /// 0.0 = identical, 1.0 = completely different.
    static func editDistance(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        guard m > 0 || n > 0 else { return 0 }
        guard m > 0 else { return 1 }
        guard n > 0 else { return 1 }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + min(prev[j - 1], prev[j], curr[j - 1])
                }
            }
            swap(&prev, &curr)
        }

        let distance = Double(prev[n])
        let maxLen = Double(max(m, n))
        return distance / maxLen
    }

    // MARK: - Thresholds

    /// Returns true if the change between old and new normalized text exceeds
    /// the summarization re-run threshold (20%).
    static func exceedsSummarizationThreshold(old: String, new: String) -> Bool {
        editDistance(old, new) > 0.20
    }

    /// Returns true if the change exceeds the task extraction re-run threshold (10%).
    /// Tasks are more brittle than summaries so the bar is lower.
    static func exceedsTaskExtractionThreshold(old: String, new: String) -> Bool {
        editDistance(old, new) > 0.10
    }
}
