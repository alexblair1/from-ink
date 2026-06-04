import ComposableArchitecture
import SwiftData
import XCTest
@testable import FromInk

/// Exercises `CalendarItemLinkValidator.reconcile` — the per-pass logic
/// that consumes `EKEventStoreChanged` and updates the persisted link
/// store. Covers:
///
/// - Orphan links (no local match, no external match) get deleted.
///   The notebook is preserved — the "notebooks survive event deletion"
///   contract.
/// - Stale local IDs get rewritten when external lookup succeeds
///   (move-between-calendars heal path).
/// - Live links with no changes go untouched.
/// - Events and reminders are reconciled separately based on `kind`.
///
/// The validator's debounce + stream-consumer plumbing is covered
/// implicitly: `reconcile` runs the work that `observeAndReconcile`
/// triggers per debounced event. Testing it directly keeps the tests
/// fast and deterministic without spinning a `TestClock` for the
/// 2-second window.
///
final class CalendarItemLinkValidatorTests: XCTestCase {

    // MARK: - Fixtures

    /// Lock-isolated table mapping `(localID, kind)` → resolution.
    /// Tests build the table, hand it to a `resolveCalendarItem` stub,
    /// and assert the stored side after `reconcile` runs.
    private final class ResolverTable: @unchecked Sendable {
        var entries: [Key: CalendarItemResolution]
        struct Key: Hashable {
            let localID: String
            let kind: CalendarItemKind
        }
        init(_ initial: [Key: CalendarItemResolution]) { self.entries = initial }
    }

    @MainActor
    private func makeFixture(
        resolverTable: ResolverTable
    ) throws -> (CalendarItemLinkService, ModelContext, EventKitService, UUID) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CalendarItemLink.self, Notebook.self,
            configurations: config
        )
        let context = container.mainContext
        let notebook = Notebook(title: "Standup")
        context.insert(notebook)
        try context.save()

        let service = CalendarItemLinkService.live(
            context: { @MainActor in container.mainContext },
            now: { Date() }
        )

        var ek = EventKitService.testValue
        ek.resolveCalendarItem = { localID, _, kind in
            resolverTable.entries[.init(localID: localID, kind: kind)]
        }

        return (service, context, ek, notebook.id)
    }

    // MARK: - Orphan deletion

    func test_reconcile_dropsLinkWhenBothLookupsFail() async throws {
        // Resolver returns nil for the link's identifiers → orphan.
        // Expectation: link deleted, notebook preserved.
        let table = ResolverTable([:])
        let (service, context, ek, notebookID) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }

        _ = try await service.create(
            "EK-orphan", "ext-orphan", .event, notebookID, nil, .createdFromItem
        )

        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )

        let counts: (Int, Int) = try await MainActor.run {
            let links = try context.fetch(FetchDescriptor<CalendarItemLink>()).count
            let notebooks = try context.fetch(FetchDescriptor<Notebook>()).count
            return (links, notebooks)
        }
        let (linkCount, notebookCount) = counts
        XCTAssertEqual(linkCount, 0)
        XCTAssertEqual(notebookCount, 1, "Notebook must survive event deletion")
    }

    func test_reconcile_preservesNotebookWithMultipleOrphans() async throws {
        // Two orphan links pointing at the same notebook. Both get
        // dropped, notebook remains.
        let table = ResolverTable([:])
        let (service, context, ek, notebookID) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }

        _ = try await service.create("e-1", nil, .event, notebookID, nil, .linked)
        _ = try await service.create("e-2", nil, .event, notebookID, nil, .linked)

        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )

        let counts: (Int, Int) = try await MainActor.run {
            let links = try context.fetch(FetchDescriptor<CalendarItemLink>()).count
            let notebooks = try context.fetch(FetchDescriptor<Notebook>()).count
            return (links, notebooks)
        }
        let (linkCount, notebookCount) = counts
        XCTAssertEqual(linkCount, 0)
        XCTAssertEqual(notebookCount, 1)
    }

    // MARK: - Heal path

    func test_reconcile_rewritesLocalIDWhenChanged() async throws {
        // EK now reports the same external ID under a different local
        // ID (the move-between-calendars case). Validator must rewrite
        // the link's local ID rather than dropping + re-creating.
        let table = ResolverTable([
            .init(localID: "EK-old", kind: .event): CalendarItemResolution(
                localIdentifier: "EK-new",
                externalIdentifier: "ext-1"
            )
        ])
        let (service, _, ek, notebookID) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }

        let original = try await service.create(
            "EK-old", "ext-1", .event, notebookID, nil, .linked
        )

        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )

        let healed = await service.lookup("EK-new", .event)
        XCTAssertNotNil(healed)
        XCTAssertEqual(healed?.id, original.id)
        let oldStill = await service.lookup("EK-old", .event)
        XCTAssertNil(oldStill)
    }

    func test_reconcile_rewritesExternalIDWhenChanged() async throws {
        // EK reports a new external ID under the same local ID — e.g.,
        // the user enabled iCloud calendar sync after the original
        // link was created. We capture the new external ID so future
        // resolutions can fall back through it.
        let table = ResolverTable([
            .init(localID: "EK-1", kind: .event): CalendarItemResolution(
                localIdentifier: "EK-1",
                externalIdentifier: "ext-new"
            )
        ])
        let (service, _, ek, notebookID) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }

        let original = try await service.create(
            "EK-1", nil, .event, notebookID, nil, .linked
        )
        XCTAssertNil(original.externalIdentifier)

        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )

        let updated = await service.lookup("EK-1", .event)
        XCTAssertEqual(updated?.externalIdentifier, "ext-new")
    }

    // MARK: - Noop path

    func test_reconcile_doesNotModifyLiveLinks() async throws {
        // Resolution matches stored values exactly. No write should
        // happen — verified by the link's `createdAt` staying as
        // originally inserted.
        let table = ResolverTable([
            .init(localID: "EK-1", kind: .event): CalendarItemResolution(
                localIdentifier: "EK-1",
                externalIdentifier: "ext-1"
            )
        ])
        let (service, _, ek, notebookID) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }
        let original = try await service.create(
            "EK-1", "ext-1", .event, notebookID, nil, .linked
        )

        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )

        let after = await service.lookup("EK-1", .event)
        XCTAssertEqual(after?.id, original.id)
        XCTAssertEqual(after?.createdAt, original.createdAt)
        XCTAssertEqual(after?.localIdentifier, "EK-1")
        XCTAssertEqual(after?.externalIdentifier, "ext-1")
    }

    // MARK: - Kind dispatch

    func test_reconcile_reconcilesEventAndReminderSeparately() async throws {
        // Two links with the same local ID, different kinds. Resolver
        // returns alive for the event, orphan for the reminder.
        // Result: event survives, reminder is dropped.
        let table = ResolverTable([
            .init(localID: "shared", kind: .event): CalendarItemResolution(
                localIdentifier: "shared",
                externalIdentifier: nil
            )
        ])
        let (service, _, ek, notebookID) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }
        _ = try await service.create(
            "shared", nil, .event, notebookID, nil, .linked
        )
        _ = try await service.create(
            "shared", nil, .reminder, notebookID, nil, .linked
        )

        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )

        let eventLookup = await service.lookup("shared", .event)
        XCTAssertNotNil(eventLookup)
        let reminderLookup = await service.lookup("shared", .reminder)
        XCTAssertNil(reminderLookup)
    }

    // MARK: - Empty store

    func test_reconcile_emptyStore_isNoOp() async throws {
        let table = ResolverTable([:])
        let (service, _, ek, _) = try await MainActor.run {
            try makeFixture(resolverTable: table)
        }
        // No links → reconcile is a no-op, must not throw.
        await CalendarItemLinkValidator.reconcile(
            linkService: service, eventKit: ek
        )
    }
}
