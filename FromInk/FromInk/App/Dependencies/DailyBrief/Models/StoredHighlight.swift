import Foundation

/// A highlight frozen at brief generation time.
/// Stored as JSON in DailyBriefRecord.highlightsData.
/// Survives even if the source calendar event is later deleted.
///
struct StoredHighlight: Codable, Equatable, Sendable {
    let category: HighlightCategory
    let icon: String
    let title: String
    let time: String
    let trailingBadge: String
    let sourceNotebookID: UUID?
    let sourcePageIndex: Int?
}
