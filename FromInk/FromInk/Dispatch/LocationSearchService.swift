import ComposableArchitecture
import Foundation
import MapKit

/// MapKit-backed location search for the Dispatch Calendar destination.
///
/// Two endpoints — autocomplete-as-you-type (via `MKLocalSearchCompleter`)
/// and resolve-on-tap (via `MKLocalSearch`). The autocomplete is a hot
/// stream that yields new suggestion arrays whenever the underlying
/// MapKit completer fires its delegate. The resolve step turns a tapped
/// `LocationSuggestion` into a concrete `ResolvedLocation` carrying lat
/// + lon so the saved EKEvent can carry an `EKStructuredLocation` and
/// Calendar.app shows the inline map preview.
///
/// No CoreLocation permission required — autocomplete is a pure
/// query→completion API, not a "near me" search.
struct LocationSearchService: Sendable {
    /// Streams suggestion arrays as the user types. The underlying
    /// `MKLocalSearchCompleter` is a single-result-set fixture, so
    /// only one stream is active at a time: when the caller invokes
    /// `suggestions` a second time, the driver explicitly finishes
    /// the prior stream before starting the new query. Each stream
    /// also tags itself with a unique id so a late `onTermination`
    /// from an abandoned stream can't finish the wrong continuation.
    var suggestions: @Sendable (String) -> AsyncStream<[LocationSuggestion]>

    /// Resolves a tapped suggestion into a full place — coordinate +
    /// formatted address. Uses the driver's cached
    /// `MKLocalSearchCompletion` (looked up by id) so MapKit
    /// disambiguates correctly even when title + subtitle would be
    /// ambiguous as a natural-language query (e.g. two "Starbucks" in
    /// the same city). Falls back to a natural-language search if the
    /// cache no longer holds the completion — the user may have
    /// typed past the suggestion they tapped.
    var resolve: @Sendable (LocationSuggestion) async throws -> ResolvedLocation
}

// MARK: - Value types

/// A single autocomplete row (title + subtitle pair). The `id` is
/// synthesized so the SwiftUI ForEach can diff on identity.
struct LocationSuggestion: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

struct ResolvedLocation: Sendable, Equatable {
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double
}

enum LocationSearchError: Error, LocalizedError, Equatable {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return AppStrings.DispatchModal.locationSearchFailed
        }
    }
}

// MARK: - DependencyKey

extension LocationSearchService: DependencyKey {
    static var liveValue: LocationSearchService {
        let driver = LocationSearchDriver()

        return LocationSearchService(
            suggestions: { query in
                let streamID = UUID()
                return AsyncStream { continuation in
                    Task { @MainActor in
                        driver.startSearch(id: streamID, query: query, continuation: continuation)
                    }
                    continuation.onTermination = { _ in
                        Task { @MainActor in
                            // Id-scoped — a late teardown from an
                            // abandoned stream can't finish the
                            // currently-active continuation.
                            driver.stopSearch(id: streamID)
                        }
                    }
                }
            },
            resolve: { suggestion in
                // Prefer the cached `MKLocalSearchCompletion` — that's
                // the disambiguated handle MapKit returned. Only fall
                // back to a natural-language search when the user has
                // typed past the completion that was tapped (rare
                // race: keystroke + tap within ~50ms).
                if let mapItem = try await driver.resolve(id: suggestion.id) {
                    return makeResolvedLocation(from: mapItem, suggestion: suggestion)
                }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = "\(suggestion.title) \(suggestion.subtitle)"
                let response = try await MKLocalSearch(request: request).start()
                guard let item = response.mapItems.first else {
                    throw LocationSearchError.notFound
                }
                return makeResolvedLocation(from: item, suggestion: suggestion)
            }
        )
    }

    static var testValue: LocationSearchService {
        LocationSearchService(
            suggestions: { _ in AsyncStream { $0.finish() } },
            resolve: { _ in
                ResolvedLocation(
                    title: "Apple Park",
                    address: "1 Apple Park Way, Cupertino, CA",
                    latitude: 37.3349, longitude: -122.0090
                )
            }
        )
    }
}

private func makeResolvedLocation(
    from item: MKMapItem,
    suggestion: LocationSuggestion
) -> ResolvedLocation {
    let coord = item.placemark.coordinate
    return ResolvedLocation(
        title: item.name ?? suggestion.title,
        address: formatAddress(item.placemark),
        latitude: coord.latitude,
        longitude: coord.longitude
    )
}

extension DependencyValues {
    var locationSearchService: LocationSearchService {
        get { self[LocationSearchService.self] }
        set { self[LocationSearchService.self] = newValue }
    }
}

// MARK: - Address formatter

/// Folds a `CLPlacemark` into a single human address line. Skips empty
/// components so we don't get "Apple Park, , , US" style artifacts.
private func formatAddress(_ placemark: CLPlacemark) -> String {
    func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
    let parts: [String?] = [
        nilIfEmpty([placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")),
        placemark.locality,
        nilIfEmpty([placemark.administrativeArea, placemark.postalCode].compactMap { $0 }.joined(separator: " ")),
        placemark.country,
    ]
    return parts.compactMap { $0 }.joined(separator: ", ")
}

// MARK: - Driver (MapKit completer + delegate)

/// Single shared `MKLocalSearchCompleter` instance, wrapped in a
/// main-actor class so the delegate callbacks can update the active
/// continuation safely.
///
/// Streams are id-tagged — `startSearch(id:…)` only replaces the
/// active continuation, and `stopSearch(id:)` only finishes the active
/// one when the ids match. This prevents a late teardown from an
/// abandoned stream from finishing the *next* stream's continuation
/// (the bug a non-id-tagged single-slot scheme has).
///
/// Each delegate update also captures `[MKLocalSearchCompletion]`
/// keyed by suggestion id so `resolve(id:)` can disambiguate via
/// `MKLocalSearch.Request(completion:)` — the official path, not the
/// brittle natural-language re-search.
@MainActor
private final class LocationSearchDriver: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var activeStreamID: UUID?
    private var activeContinuation: AsyncStream<[LocationSuggestion]>.Continuation?
    /// Completion cache for `resolve(id:)`. Replaced wholesale on each
    /// delegate update — only the latest results' completions are
    /// guaranteed retrievable. A user who taps a suggestion that's
    /// already been superseded falls through to the natural-language
    /// search path in `LocationSearchService.resolve`.
    private var cachedCompletions: [String: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func startSearch(
        id: UUID,
        query: String,
        continuation: AsyncStream<[LocationSuggestion]>.Continuation
    ) {
        // Finish the previous stream and install this one. Id-tagging
        // makes the swap safe against out-of-order teardowns.
        activeContinuation?.finish()
        activeStreamID = id
        activeContinuation = continuation

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Empty query → emit nothing and clear the cache.
            // `completer.queryFragment = ""` doesn't reliably clear
            // the held results in older MapKit revisions.
            cachedCompletions.removeAll()
            continuation.yield([])
            return
        }
        completer.queryFragment = query
    }

    /// Finish the stream only if it's still the active one. A late
    /// `onTermination` from a stream that's already been superseded
    /// is a no-op — the new stream stays connected.
    func stopSearch(id: UUID) {
        guard activeStreamID == id else { return }
        activeContinuation?.finish()
        activeContinuation = nil
        activeStreamID = nil
    }

    /// Look up the cached `MKLocalSearchCompletion` for a tapped
    /// suggestion and resolve it via `MKLocalSearch`. Returns nil
    /// when the completion has been evicted (the user kept typing
    /// after the suggestion was emitted) — caller should fall back
    /// to a natural-language search.
    func resolve(id: String) async throws -> MKMapItem? {
        guard let completion = cachedCompletions[id] else { return nil }
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.first
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak self] in
            guard let self else { return }
            var cache: [String: MKLocalSearchCompletion] = [:]
            let suggestions = results.map { result -> LocationSuggestion in
                let id = "\(result.title)|\(result.subtitle)"
                cache[id] = result
                return LocationSuggestion(id: id, title: result.title, subtitle: result.subtitle)
            }
            self.cachedCompletions = cache
            self.activeContinuation?.yield(suggestions)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            // Yield empty rather than finishing — the user might fix
            // the query (e.g. typos clear up) and we want the next
            // delegate fire to land in this same stream.
            self?.activeContinuation?.yield([])
        }
    }
}
