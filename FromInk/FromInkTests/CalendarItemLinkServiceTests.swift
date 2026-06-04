import SwiftData
import XCTest
@testable import FromInk

/// Exercises `CalendarItemLinkService.live(context:)` against an
/// in-memory ModelContainer. Covers:
///
/// - `lookup` returns nil for unlinked items, populated snapshot when a
///   link exists.
/// - `lookupBatch` returns one row per matched identifier, ignores
///   unmatched IDs, and tolerates duplicates in the input list.
/// - `create` writes a record and refuses duplicates with
///   `CalendarItemLinkError.duplicate(existing:)` — strict 1:1 at the
///   service boundary.
/// - `delete` removes the link without touching the notebook.
/// - `rewriteIdentifiers` updates `localIdentifier` and
///   `externalIdentifier` in place (the auto-heal path).
/// - `allLinks` returns sorted snapshots.
///
final class CalendarItemLinkServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// Returns a service backed by a fresh in-memory container, and the
    /// MainActor context the test can use to seed/inspect state
    /// directly. Each test gets isolated storage.
    @MainActor
    private func makeService() throws -> (CalendarItemLinkService, ModelContext, UUID) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CalendarItemLink.self, Notebook.self,
            configurations: config
        )
        let context = container.mainContext
        let notebook = Notebook(title: "Test notebook")
        context.insert(notebook)
        try context.save()

        let service = CalendarItemLinkService.live(
            context: { @MainActor in container.mainContext },
            now: { Date() }
        )
        return (service, context, notebook.id)
    }

    // MARK: - lookup

    func test_lookup_returnsNilWhenUnlinked() async throws {
        let (service, _, _) = try await MainActor.run { try makeService() }
        let result = await service.lookup("non-existent", .event)
        XCTAssertNil(result)
    }

    func test_lookup_returnsSnapshotWhenLinked() async throws {
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        _ = try await service.create(
            "EK-1", "ext-1", .event, notebookID, nil, .linked
        )

        let result = await service.lookup("EK-1", .event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.localIdentifier, "EK-1")
        XCTAssertEqual(result?.kind, .event)
        XCTAssertEqual(result?.notebookID, notebookID)
    }

    func test_lookup_distinguishesEventFromReminder() async throws {
        // Same local identifier under both kinds — the schema doesn't
        // forbid this (separate primary domains in EventKit), but
        // `lookup` must filter on `kindRaw` so a reminder lookup doesn't
        // accidentally return an event row.
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        _ = try await service.create(
            "shared-id", nil, .event, notebookID, nil, .linked
        )

        let asReminder = await service.lookup("shared-id", .reminder)
        XCTAssertNil(asReminder)
        let asEvent = await service.lookup("shared-id", .event)
        XCTAssertNotNil(asEvent)
    }

    // MARK: - lookupBatch

    func test_lookupBatch_returnsOnlyMatchedIdentifiers() async throws {
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        _ = try await service.create("a", nil, .event, notebookID, nil, .linked)
        _ = try await service.create("c", nil, .event, notebookID, nil, .linked)

        let result = await service.lookupBatch(["a", "b", "c"], .event)
        XCTAssertEqual(Set(result.keys), Set(["a", "c"]))
    }

    func test_lookupBatch_dedupesInputIdentifiers() async throws {
        // The adapter passes a flat array — sometimes containing the
        // same identifier twice (an event that appears in two visible
        // brief tabs, say). The batch query must dedupe so the
        // dictionary builder doesn't surface a uniqueness collision.
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        _ = try await service.create("dup", nil, .event, notebookID, nil, .linked)

        let result = await service.lookupBatch(["dup", "dup", "dup"], .event)
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["dup"])
    }

    func test_lookupBatch_emptyInput_returnsEmpty() async throws {
        let (service, _, _) = try await MainActor.run { try makeService() }
        let result = await service.lookupBatch([], .event)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - create

    func test_create_writesLinkToContext() async throws {
        let (service, context, notebookID) = try await MainActor.run { try makeService() }

        let snapshot = try await service.create(
            "EK-1", "ext-1", .event, notebookID, nil, .createdFromItem
        )
        XCTAssertEqual(snapshot.localIdentifier, "EK-1")
        XCTAssertEqual(snapshot.externalIdentifier, "ext-1")
        XCTAssertEqual(snapshot.kind, .event)
        XCTAssertEqual(snapshot.source, .createdFromItem)
        XCTAssertEqual(snapshot.notebookID, notebookID)

        let stored = try await MainActor.run {
            try context.fetch(FetchDescriptor<CalendarItemLink>())
        }
        XCTAssertEqual(stored.count, 1)
    }

    func test_create_duplicate_throws() async throws {
        // CloudKit forbids `@Attribute(.unique)`, so duplicate
        // prevention is enforced at the service. The error carries the
        // existing snapshot so the caller (action sheet) can route the
        // user to the existing link rather than show a re-link option.
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        let original = try await service.create(
            "EK-1", nil, .event, notebookID, nil, .linked
        )

        do {
            _ = try await service.create(
                "EK-1", nil, .event, notebookID, nil, .linked
            )
            XCTFail("Expected duplicate error")
        } catch let error as CalendarItemLinkError {
            switch error {
            case .duplicate(let existing):
                XCTAssertEqual(existing.id, original.id)
                XCTAssertEqual(existing.notebookID, notebookID)
            default:
                XCTFail("Expected .duplicate, got \(error)")
            }
        }
    }

    func test_create_unknownNotebookID_throws() async throws {
        let (service, _, _) = try await MainActor.run { try makeService() }
        do {
            _ = try await service.create(
                "EK-1", nil, .event, UUID(), nil, .linked
            )
            XCTFail("Expected notebookNotFound")
        } catch CalendarItemLinkError.notebookNotFound {
            // expected
        }
    }

    // MARK: - delete

    func test_delete_removesLink_butNotNotebook() async throws {
        let (service, context, notebookID) = try await MainActor.run { try makeService() }
        let link = try await service.create(
            "EK-1", nil, .event, notebookID, nil, .createdFromItem
        )

        try await service.delete(link.id)

        let counts: (Int, Int) = try await MainActor.run {
            let links = try context.fetch(FetchDescriptor<CalendarItemLink>()).count
            let notebooks = try context.fetch(FetchDescriptor<Notebook>()).count
            return (links, notebooks)
        }
        let (linkCount, notebookCount) = counts
        XCTAssertEqual(linkCount, 0)
        XCTAssertEqual(notebookCount, 1, "Deleting a link must never delete the notebook")
    }

    func test_delete_unknownID_isNoOp() async throws {
        let (service, _, _) = try await MainActor.run { try makeService() }
        // Validator may call delete on a link that just got cleaned up
        // by a concurrent pass. Missing rows should be silent.
        try await service.delete(UUID())
    }

    // MARK: - rewriteIdentifiers

    func test_rewriteIdentifiers_updatesInPlace() async throws {
        // Auto-heal path: EK reports the same external ID under a new
        // local ID (move-between-calendars). The validator rewrites the
        // local + external on the link record without re-linking.
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        let link = try await service.create(
            "EK-old", "ext-1", .event, notebookID, nil, .linked
        )

        try await service.rewriteIdentifiers(link.id, "EK-new", "ext-1-updated")

        let resolved = await service.lookup("EK-new", .event)
        let result = try XCTUnwrap(resolved)
        XCTAssertEqual(result.id, link.id)
        XCTAssertEqual(result.externalIdentifier, "ext-1-updated")
        let oldLookup = await service.lookup("EK-old", .event)
        XCTAssertNil(oldLookup)
    }

    func test_rewriteIdentifiers_unknownID_isNoOp() async throws {
        let (service, _, _) = try await MainActor.run { try makeService() }
        try await service.rewriteIdentifiers(UUID(), "new", nil)
    }

    // MARK: - allLinks

    func test_allLinks_returnsSortedSnapshots() async throws {
        // Sort is by createdAt ascending so the validator processes in
        // insertion order — deterministic logging when records share
        // identifiers (which they shouldn't, but the sort makes
        // reproduction stable when they do).
        let (service, _, notebookID) = try await MainActor.run { try makeService() }
        _ = try await service.create("c", nil, .event, notebookID, nil, .linked)
        _ = try await service.create("a", nil, .event, notebookID, nil, .linked)
        _ = try await service.create("b", nil, .event, notebookID, nil, .linked)

        let all = await service.allLinks()
        XCTAssertEqual(all.count, 3)
        // createdAt is `Date()` per the service init — within the same
        // run, monotonic by insertion order. Strict ascending.
        let createdAts = all.map(\.createdAt)
        XCTAssertEqual(createdAts, createdAts.sorted())
    }
}
