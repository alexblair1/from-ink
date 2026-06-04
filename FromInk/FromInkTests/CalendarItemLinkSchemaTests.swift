import SwiftData
import XCTest
@testable import FromInk

/// Pins the persistence contract for `CalendarItemLink`:
///
/// - Insert + fetch roundtrip preserves every field.
/// - Enum properties (`kindRaw`, `sourceRaw`) round-trip through their
///   computed accessors.
/// - The Notebook ↔ CalendarItemLink relationship cascades from the
///   parent side — deleting a notebook removes its link records, the
///   asymmetry the orphan-link validator relies on.
/// - Deleting a link never deletes the notebook (the opposite
///   direction). Honors the "notebooks survive event deletion" rule.
///
/// All assertions run against an in-memory `ModelContainer`. CloudKit
/// is not exercised — these tests validate the SwiftData shape that
/// CloudKit will eventually sync. The lack of unique constraints
/// (forbidden by CloudKit) is checked separately at the service layer
/// (`CalendarItemLinkServiceTests.test_create_duplicate_throws`).
///
final class CalendarItemLinkSchemaTests: XCTestCase {

    // MARK: - Container

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CalendarItemLink.self, Notebook.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - Roundtrip

    @MainActor
    func test_insertAndFetch_preservesAllFields() throws {
        let ctx = try makeContext()
        let notebookID = UUID()
        let linkID = UUID()
        let pageID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_780_000_000)

        let notebook = Notebook(id: notebookID, title: "Standup")
        ctx.insert(notebook)

        let link = CalendarItemLink(
            id: linkID,
            localIdentifier: "EK-event-1",
            externalIdentifier: "external-1",
            kind: .event,
            source: .linked,
            notebook: notebook,
            pageID: pageID,
            createdAt: createdAt
        )
        ctx.insert(link)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CalendarItemLink>()).first
        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.id, linkID)
        XCTAssertEqual(unwrapped.localIdentifier, "EK-event-1")
        XCTAssertEqual(unwrapped.externalIdentifier, "external-1")
        XCTAssertEqual(unwrapped.kind, .event)
        XCTAssertEqual(unwrapped.source, .linked)
        XCTAssertEqual(unwrapped.pageID, pageID)
        XCTAssertEqual(unwrapped.createdAt, createdAt)
        XCTAssertEqual(unwrapped.notebook?.id, notebookID)
    }

    // MARK: - Enum round-tripping

    @MainActor
    func test_kindAndSource_roundTripThroughRawStorage() throws {
        let ctx = try makeContext()
        let notebook = Notebook(title: "n")
        ctx.insert(notebook)

        let reminderLink = CalendarItemLink(
            localIdentifier: "r-1",
            kind: .reminder,
            source: .createdFromItem,
            notebook: notebook,
            createdAt: Date.distantPast
        )
        ctx.insert(reminderLink)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CalendarItemLink>()).first
        XCTAssertEqual(fetched?.kind, .reminder)
        XCTAssertEqual(fetched?.source, .createdFromItem)
        // Raw storage matches the rawValue — important for `#Predicate`
        // queries that need to compare against `kindRaw` directly
        // (computed properties aren't predicate-readable).
        XCTAssertEqual(fetched?.kindRaw, "reminder")
        XCTAssertEqual(fetched?.sourceRaw, "createdFromItem")
    }

    // MARK: - Default values

    @MainActor
    func test_defaultsAreCloudKitSafe() throws {
        // Per the data model EDD: every persisted property must have a
        // default. Inserting a link with the minimum required arguments
        // and confirming defaults populate verifies the rule.
        let ctx = try makeContext()
        let notebook = Notebook(title: "n")
        ctx.insert(notebook)

        let link = CalendarItemLink(
            localIdentifier: "x",
            kind: .event,
            source: .linked,
            notebook: notebook,
            createdAt: Date.distantPast
        )
        ctx.insert(link)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<CalendarItemLink>()).first)
        XCTAssertNil(fetched.externalIdentifier)
        XCTAssertNil(fetched.pageID)
    }

    // MARK: - Cascade semantics

    @MainActor
    func test_deletingNotebook_cascadesToLinks() throws {
        let ctx = try makeContext()
        let notebook = Notebook(title: "Standup")
        ctx.insert(notebook)

        let link1 = CalendarItemLink(
            localIdentifier: "e-1",
            kind: .event,
            source: .linked,
            notebook: notebook,
            createdAt: Date.distantPast
        )
        let link2 = CalendarItemLink(
            localIdentifier: "e-2",
            kind: .event,
            source: .linked,
            notebook: notebook,
            createdAt: Date.distantPast
        )
        ctx.insert(link1)
        ctx.insert(link2)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CalendarItemLink>()).count, 2)

        ctx.delete(notebook)
        try ctx.save()

        // Cascade is the parent-side rule on Notebook.calendarLinks.
        // Both links should be gone; the notebook is gone. The
        // asymmetry (deleting links never deletes notebooks) is the
        // next test.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CalendarItemLink>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Notebook>()).count, 0)
    }

    @MainActor
    func test_deletingLink_doesNotDeleteNotebook() throws {
        // The defining requirement: notebooks survive event deletion.
        // The orphan-link validator removes the link record only; the
        // notebook stays. This test pins the SwiftData shape that
        // enables that behavior — no cascade rule in the link → notebook
        // direction.
        let ctx = try makeContext()
        let notebook = Notebook(title: "Standup")
        ctx.insert(notebook)

        let link = CalendarItemLink(
            localIdentifier: "e-1",
            kind: .event,
            source: .createdFromItem,
            notebook: notebook,
            createdAt: Date.distantPast
        )
        ctx.insert(link)
        try ctx.save()

        ctx.delete(link)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CalendarItemLink>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Notebook>()).count, 1)
    }

    // MARK: - Snapshot

    @MainActor
    func test_snapshot_carriesDenormalizedNotebookTitle() throws {
        // The adapter consumes `Snapshot`, not the `@Model`. Notebook
        // title must come along on the snapshot so the action sheet can
        // render "Open notebook: ___" without a second fetch.
        let ctx = try makeContext()
        let notebook = Notebook(title: "Quarterly Planning")
        ctx.insert(notebook)

        let link = CalendarItemLink(
            localIdentifier: "e-1",
            kind: .event,
            source: .linked,
            notebook: notebook,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        ctx.insert(link)
        try ctx.save()

        let snapshot = link.snapshot
        XCTAssertEqual(snapshot.notebookID, notebook.id)
        XCTAssertEqual(snapshot.notebookTitle, "Quarterly Planning")
        XCTAssertEqual(snapshot.kind, .event)
        XCTAssertEqual(snapshot.source, .linked)
    }

    @MainActor
    func test_snapshot_handlesNullifiedNotebook() throws {
        // If the cascade is bypassed (data corruption, partial sync)
        // and a link has no notebook, the snapshot still renders without
        // crashing. The downstream UI treats `notebookID == nil` as a
        // dead link, but the snapshot itself must not throw.
        let ctx = try makeContext()
        let link = CalendarItemLink(
            localIdentifier: "e-1",
            kind: .event,
            source: .linked,
            notebook: nil,
            createdAt: Date.distantPast
        )
        ctx.insert(link)
        try ctx.save()

        let snapshot = link.snapshot
        XCTAssertNil(snapshot.notebookID)
        XCTAssertEqual(snapshot.notebookTitle, "")
    }
}
