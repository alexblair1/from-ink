import ComposableArchitecture
import Foundation
import SwiftData
import os

/// TCA dependency that owns the persistence + lookup surface for
/// `CalendarItemLink`. Reducers and adapters interact with this client
/// instead of touching `ModelContext` directly — keeps SwiftData out of
/// `State` (per `data_layer_edd.md`) and gives us a single seam to mock
/// in tests.
///
/// All closures are `@Sendable` and async. Live implementations dispatch
/// onto the main actor to read/write the `mainContext` from the synced
/// container. Hot paths use `lookupBatch` — one query per render rather
/// than N — to keep the brief adapter cheap.
///
struct CalendarItemLinkService: Sendable {
    /// Single-identifier lookup. Returns the snapshot when a link exists
    /// for the given EK identifier, nil when unlinked.
    var lookup: @Sendable (
        _ localIdentifier: String,
        _ kind: CalendarItemKind
    ) async -> CalendarItemLink.Snapshot?

    /// Batch lookup keyed by `localIdentifier`. Returns a dictionary
    /// holding only the identifiers with a live link record. The brief
    /// adapter calls this once per render with the full list of visible
    /// event/reminder IDs to avoid N round-trips through the context.
    var lookupBatch: @Sendable (
        _ localIdentifiers: [String],
        _ kind: CalendarItemKind
    ) async -> [String: CalendarItemLink.Snapshot]

    /// Create a new link. Throws `CalendarItemLinkError.duplicate` when
    /// a link already exists for `(localIdentifier, kind)` — enforces
    /// the strict 1:1 rule at the service boundary, since CloudKit
    /// forbids `@Attribute(.unique)`. Callers that want "navigate to
    /// existing" semantics should call `lookup` first.
    var create: @Sendable (
        _ localIdentifier: String,
        _ externalIdentifier: String?,
        _ kind: CalendarItemKind,
        _ notebookID: UUID,
        _ pageID: UUID?,
        _ source: CalendarItemLinkSource
    ) async throws -> CalendarItemLink.Snapshot

    /// Remove a link by its record ID. Used by the action sheet's
    /// "unlink" affordance (V2) and by the orphan-link validator.
    /// Never touches the notebook.
    var delete: @Sendable (_ linkID: UUID) async throws -> Void

    /// Rewrite the stored `localIdentifier` (and optionally
    /// `externalIdentifier`) on an existing link. Invoked by the
    /// validator when EK reports the item under a new local ID — e.g.,
    /// after the user moves the event to a different calendar.
    var rewriteIdentifiers: @Sendable (
        _ linkID: UUID,
        _ newLocalIdentifier: String,
        _ newExternalIdentifier: String?
    ) async throws -> Void

    /// Enumerate every link. Hot path for the validator's full-pass
    /// integrity check on `EKEventStoreChanged`. Returns snapshots so
    /// the validator never touches `@Model` objects across the await
    /// boundary.
    var allLinks: @Sendable () async -> [CalendarItemLink.Snapshot]
}

// MARK: - Errors

enum CalendarItemLinkError: Error {
    /// A link already exists for the requested `(localIdentifier, kind)`.
    /// Carries the existing snapshot so the caller can redirect the user
    /// to that link rather than presenting a re-link option.
    case duplicate(existing: CalendarItemLink.Snapshot)
    /// `notebookID` did not resolve to a `Notebook`. Either the notebook
    /// was deleted between picker dismissal and link creation, or the
    /// caller supplied a stale UUID.
    case notebookNotFound
    /// Storage layer rejected the write (e.g., context save failure).
    /// The description is `error.localizedDescription` from the
    /// underlying SwiftData error, captured here for telemetry.
    case persistence(description: String)
}

// MARK: - DependencyValues

extension DependencyValues {
    var calendarItemLinkService: CalendarItemLinkService {
        get { self[CalendarItemLinkService.self] }
        set { self[CalendarItemLinkService.self] = newValue }
    }
}

// MARK: - DependencyKey

extension CalendarItemLinkService: DependencyKey {
    /// CRITICAL: `liveValue` must NOT silently delegate to other
    /// dependencies' fatal stubs — that hides install-order bugs behind
    /// inner closures and fails at the first request, not at the point
    /// of misuse. Crash loudly here instead. The real implementation is
    /// wired by `AppDependencyContainer.install(into:)` at app launch.
    /// Same pattern as `SyncedModelContextDependency.liveValue`.
    static let liveValue: CalendarItemLinkService = CalendarItemLinkService(
        lookup: { _, _ in fatalErrorNotInstalled() },
        lookupBatch: { _, _ in fatalErrorNotInstalled() },
        create: { _, _, _, _, _, _ in fatalErrorNotInstalled() },
        delete: { _ in fatalErrorNotInstalled() },
        rewriteIdentifiers: { _, _, _ in fatalErrorNotInstalled() },
        allLinks: { fatalErrorNotInstalled() }
    )

    /// `testValue`: in-memory ModelContainer with a focused subset of
    /// the schema. Tests that need richer fixtures construct their own
    /// container and call `.live(context:now:)` directly.
    static var testValue: CalendarItemLinkService {
        let container = try! ModelContainer(
            for: CalendarItemLink.self, Notebook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return .live(
            context: { @MainActor in container.mainContext },
            now: { Date() }
        )
    }
}

@Sendable
private func fatalErrorNotInstalled() -> Never {
    fatalError(
        "calendarItemLinkService.liveValue accessed before install. " +
        "Call AppDependencyContainer.install(into:) at app launch."
    )
}

// MARK: - Factory

extension CalendarItemLinkService {
    private static let log = Logger(subsystem: "com.fromink.app", category: "CalendarItemLink")

    /// Build a live service from a `@MainActor`-resolved context
    /// supplier plus a `now` clock. Factored so the dependency container
    /// can wire the synced context + `calendarContext.now()`; tests
    /// inject isolated in-memory contexts + deterministic clocks. The
    /// `now` injection is the dates EDD's "no bare `Date()` outside
    /// `CalendarContext.liveValue`" rule.
    static func live(
        context: @escaping @Sendable @MainActor () -> ModelContext,
        now: @escaping @Sendable () -> Date
    ) -> CalendarItemLinkService {
        CalendarItemLinkService(
            lookup: { localID, kind in
                await MainActor.run {
                    do {
                        return try fetchOne(
                            localID: localID,
                            kind: kind,
                            in: context()
                        )?.snapshot
                    } catch {
                        log.error("lookup failed: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            },
            lookupBatch: { localIDs, kind in
                guard !localIDs.isEmpty else { return [:] }
                let unique = Array(Set(localIDs))
                return await MainActor.run {
                    let kindRaw = kind.rawValue
                    do {
                        // Single fetch with an `IN` predicate. SwiftData
                        // compiles this to one SQL query, regardless of
                        // batch size — far cheaper than N point lookups.
                        let descriptor = FetchDescriptor<CalendarItemLink>(
                            predicate: #Predicate { link in
                                unique.contains(link.localIdentifier)
                                    && link.kindRaw == kindRaw
                            }
                        )
                        let rows = try context().fetch(descriptor)
                        return Dictionary(
                            rows.map { ($0.localIdentifier, $0.snapshot) },
                            uniquingKeysWith: { current, _ in current }
                        )
                    } catch {
                        log.error("lookupBatch failed: \(error.localizedDescription, privacy: .public)")
                        return [:]
                    }
                }
            },
            create: { localID, externalID, kind, notebookID, pageID, source in
                try await MainActor.run {
                    let ctx = context()

                    // Enforce 1:1 at the service boundary. CloudKit
                    // forbids `@Attribute(.unique)`, so duplicate
                    // prevention is application-layer.
                    if let existing = try fetchOne(localID: localID, kind: kind, in: ctx) {
                        throw CalendarItemLinkError.duplicate(existing: existing.snapshot)
                    }

                    // Resolve the notebook before constructing the link.
                    // Pulling a stale UUID through the picker is rare
                    // but possible if the user deletes the notebook in
                    // a parallel context between selection and confirm.
                    let notebookFetch = FetchDescriptor<Notebook>(
                        predicate: #Predicate { $0.id == notebookID }
                    )
                    guard let notebook = try ctx.fetch(notebookFetch).first else {
                        throw CalendarItemLinkError.notebookNotFound
                    }

                    let link = CalendarItemLink(
                        localIdentifier: localID,
                        externalIdentifier: externalID,
                        kind: kind,
                        source: source,
                        notebook: notebook,
                        pageID: pageID,
                        createdAt: now()
                    )
                    ctx.insert(link)
                    do {
                        try ctx.save()
                    } catch {
                        throw CalendarItemLinkError.persistence(description: error.localizedDescription)
                    }
                    return link.snapshot
                }
            },
            delete: { linkID in
                try await MainActor.run {
                    let ctx = context()
                    let descriptor = FetchDescriptor<CalendarItemLink>(
                        predicate: #Predicate { $0.id == linkID }
                    )
                    guard let link = try ctx.fetch(descriptor).first else { return }
                    ctx.delete(link)
                    do {
                        try ctx.save()
                    } catch {
                        throw CalendarItemLinkError.persistence(description: error.localizedDescription)
                    }
                }
            },
            rewriteIdentifiers: { linkID, newLocalID, newExternalID in
                try await MainActor.run {
                    let ctx = context()
                    let descriptor = FetchDescriptor<CalendarItemLink>(
                        predicate: #Predicate { $0.id == linkID }
                    )
                    guard let link = try ctx.fetch(descriptor).first else { return }
                    link.localIdentifier = newLocalID
                    link.externalIdentifier = newExternalID
                    do {
                        try ctx.save()
                    } catch {
                        throw CalendarItemLinkError.persistence(description: error.localizedDescription)
                    }
                }
            },
            allLinks: {
                await MainActor.run {
                    do {
                        // Ascending by `createdAt` so validator passes
                        // process links in stable order across runs —
                        // helps reproduce bugs from telemetry logs.
                        let descriptor = FetchDescriptor<CalendarItemLink>(
                            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
                        )
                        return try context().fetch(descriptor).map(\.snapshot)
                    } catch {
                        log.error("allLinks failed: \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }
        )
    }

    /// Shared helper — fetches a single link by `(localIdentifier, kind)`.
    /// Throws on context failure; returns nil when the record doesn't
    /// exist (no `try?` ambiguity at the call sites).
    @MainActor
    private static func fetchOne(
        localID: String,
        kind: CalendarItemKind,
        in ctx: ModelContext
    ) throws -> CalendarItemLink? {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<CalendarItemLink>(
            predicate: #Predicate { link in
                link.localIdentifier == localID && link.kindRaw == kindRaw
            }
        )
        return try ctx.fetch(descriptor).first
    }
}
