import ComposableArchitecture
import Foundation

/// TCA dependency that runs library searches. Decoupled from any
/// presentation surface — the same client backs `LibraryBrowseView`,
/// the future notebook-picker-with-search variant, and any quick-
/// switcher / global search feature.
///
/// **V1 implementation** composes the existing `NotebookClient`
/// fetch-all methods and filters in-memory. Fine up to a few thousand
/// items; beyond that a SwiftData `#Predicate` query or a dedicated
/// FTS index would be the next step. The dependency surface (single
/// `search(query:scope:)` closure) doesn't change — only the live
/// implementation does.
///
/// **Ranking** is a two-tier sort:
///   1. **Title starts-with `query`** ranks above title contains-only.
///   2. Within each tier, items are sorted most-recent first
///      (`rankingDate` descending).
///
/// Locale-insensitive substring matching via `localizedCaseInsensitiveContains`
/// so user queries like "ce" match "Certificate" regardless of
/// capitalization or accents.
///
struct LibrarySearchService: Sendable {
    var search: @Sendable (
        _ query: String,
        _ scope: LibrarySearchScope
    ) async throws -> [LibrarySearchResult]
}

// MARK: - DependencyValues

extension DependencyValues {
    var librarySearchService: LibrarySearchService {
        get { self[LibrarySearchService.self] }
        set { self[LibrarySearchService.self] = newValue }
    }
}

// MARK: - DependencyKey

extension LibrarySearchService: DependencyKey {
    /// CRITICAL: live value is a fatalError stub — same pattern as
    /// `CalendarItemLinkService`. The real wiring happens in
    /// `AppDependencyContainer.install(into:)`.
    static let liveValue: LibrarySearchService = LibrarySearchService(
        search: { _, _ in
            fatalError(
                "librarySearchService.liveValue accessed before install. " +
                "Call AppDependencyContainer.install(into:) at app launch."
            )
        }
    )

    /// `testValue` returns an empty list for any query. Tests that
    /// need specific results override with their own stub via
    /// `withDependencies { $0.librarySearchService = ... }`.
    static let testValue: LibrarySearchService = LibrarySearchService(
        search: { _, _ in [] }
    )
}

// MARK: - Factory

extension LibrarySearchService {
    /// Build a live service composed over `NotebookClient`. The
    /// container wires this with the same client the rest of the app
    /// uses, so writes from elsewhere (new notebook, deleted PDF) are
    /// visible to the next search immediately.
    static func live(notebookClient: NotebookClient) -> LibrarySearchService {
        LibrarySearchService(
            search: { rawQuery, scope in
                let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    // Empty query = full library, ranked by recency.
                    // The "browse all" surface relies on this — no
                    // separate "list everything" call needed.
                    return try await fetchAll(scope: scope, client: notebookClient)
                }

                async let notebooks = scope.contains(.notebooks)
                    ? notebookClient.fetchAllNotebooks().map(LibrarySearchResult.notebook)
                    : []
                async let folders = scope.contains(.folders)
                    ? notebookClient.fetchAllFolders().map(LibrarySearchResult.folder)
                    : []
                async let pdfs = scope.contains(.pdfs)
                    ? notebookClient.fetchAllPDFs().map(LibrarySearchResult.pdf)
                    : []

                let merged = try await notebooks + folders + pdfs
                return rankAndFilter(merged, query: query)
            }
        )
    }

    /// "Empty query" path — return everything in scope, ranked by
    /// recency. Surfaced as a separate helper so the empty-query
    /// branch in `search` reads in one line.
    private static func fetchAll(
        scope: LibrarySearchScope,
        client: NotebookClient
    ) async throws -> [LibrarySearchResult] {
        async let notebooks = scope.contains(.notebooks)
            ? client.fetchAllNotebooks().map(LibrarySearchResult.notebook)
            : []
        async let folders = scope.contains(.folders)
            ? client.fetchAllFolders().map(LibrarySearchResult.folder)
            : []
        async let pdfs = scope.contains(.pdfs)
            ? client.fetchAllPDFs().map(LibrarySearchResult.pdf)
            : []
        let merged = try await notebooks + folders + pdfs
        return merged.sorted { $0.rankingDate > $1.rankingDate }
    }

    /// Two-tier rank: title prefix matches above substring matches,
    /// each tier sorted most-recent first. Pure function — easy to
    /// test independently of the SwiftData layer.
    static func rankAndFilter(
        _ items: [LibrarySearchResult],
        query: String
    ) -> [LibrarySearchResult] {
        let lowered = query.lowercased()
        let matches = items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
        let prefixHits = matches
            .filter { $0.title.lowercased().hasPrefix(lowered) }
            .sorted { $0.rankingDate > $1.rankingDate }
        let substringHits = matches
            .filter { !$0.title.lowercased().hasPrefix(lowered) }
            .sorted { $0.rankingDate > $1.rankingDate }
        return prefixHits + substringHits
    }
}
