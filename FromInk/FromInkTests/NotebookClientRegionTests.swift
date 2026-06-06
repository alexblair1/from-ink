import ComposableArchitecture
import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import FromInk

/// Pins the live `NotebookClient` behavior for the four `NoteRegion`
/// verbs (`addRegion`, `updateRegionHeader`, `updateRegionLink`,
/// `deleteRegion`). Each test wires a fresh in-memory
/// `SyncedModelContextDependency` + a fixed `CalendarContext`, calls
/// the verb under test, then asserts directly against the SwiftData
/// store (not just the returned snapshot) so persistence-side
/// regressions surface.
///
/// The "happy" roundtrips overlap with `NoteRegionSchemaTests`
/// intentionally — schema tests pin model shape, these pin the
/// client's mutation rules (header trim/collapse, link union
/// exclusivity on update, `regionNotFound` on missing ID, and the
/// `notebook.modifiedAt` bump that drives library re-sorting).
///
/// Bump assertions use a **two-clock** pattern: setup work runs
/// against a client clocked at `earlier`, and the verb under test
/// runs against a separate client clocked at `fixedNow` over the
/// same `ModelContext`. If the verb didn't bump, the assertion
/// would observe `earlier` and fail — a single-clock setup would
/// silently pass either way.
final class NotebookClientRegionTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    @MainActor
    private func seedNotebookPage(
        context modelContext: SyncedModelContextDependency
    ) throws -> (notebookID: UUID, pageID: UUID) {
        let ctx = modelContext.context()
        let notebook = Notebook(
            title: "Test",
            createdAt: earlier,
            modifiedAt: earlier
        )
        ctx.insert(notebook)
        let page = NotePage(notebook: notebook)
        ctx.insert(page)
        try ctx.save()
        return (notebook.id, page.id)
    }

    /// Builds a `NotebookClient` clocked at `now`. Pass `modelContext`
    /// to bind a second client to an existing store (the two-clock
    /// pattern used by `modifiedAt`-bump tests). Omit to spin up a
    /// fresh in-memory store.
    private func makeClient(
        on modelContext: SyncedModelContextDependency? = nil,
        now: Date
    ) -> (NotebookClient, SyncedModelContextDependency) {
        let ctx = modelContext ?? SyncedModelContextDependency.inMemory()
        let client = NotebookClient.live(
            modelContext: ctx,
            calendarContext: CalendarContext.fixed(now: now)
        )
        return (client, ctx)
    }

    // MARK: - addRegion

    @MainActor
    func test_addRegion_unknownPage_throwsPageNotFound() async {
        let (client, _) = makeClient(now: fixedNow)
        let missingID = UUID()

        do {
            _ = try await client.addRegion(missingID, .zero, nil, nil)
            XCTFail("Expected pageNotFound")
        } catch let error as NotebookClientError {
            XCTAssertEqual(error, .pageNotFound(missingID))
        } catch {
            XCTFail("Expected NotebookClientError, got \(error)")
        }
    }

    // MARK: - updateRegionHeader

    @MainActor
    func test_updateRegionHeader_setsText_andBumpsModifiedAt() async throws {
        let (setupClient, modelContext) = makeClient(now: earlier)
        let (notebookID, pageID) = try seedNotebookPage(context: modelContext)
        let created = try await setupClient.addRegion(
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10), nil, nil
        )

        let (exerciseClient, _) = makeClient(on: modelContext, now: fixedNow)
        let snap = try await exerciseClient.updateRegionHeader(created.id, "Section A")

        XCTAssertEqual(snap.headerOCRText, "Section A")
        let ctx = modelContext.context()
        let region = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<NoteRegion>()).first { $0.id == created.id }
        )
        XCTAssertEqual(region.headerOCRText, "Section A")
        let notebook = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<Notebook>()).first { $0.id == notebookID }
        )
        XCTAssertEqual(notebook.modifiedAt, fixedNow,
                       "updateRegionHeader must bump the parent notebook's modifiedAt")
    }

    @MainActor
    func test_updateRegionHeader_nilText_clearsHeader() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)
        let created = try await client.addRegion(
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10), "Old", nil
        )

        let snap = try await client.updateRegionHeader(created.id, nil)

        XCTAssertNil(snap.headerOCRText)
    }

    @MainActor
    func test_updateRegionHeader_whitespaceOnly_collapsesToNil() async throws {
        // The header-trim contract: whitespace-only text is
        // semantically "no header" and must collapse to nil so the
        // badge disappears + `hasAnyAssociation` reads false.
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)
        let created = try await client.addRegion(
            pageID, .zero, "Old", nil
        )

        let snap = try await client.updateRegionHeader(created.id, "   \n  ")

        XCTAssertNil(snap.headerOCRText)
    }

    @MainActor
    func test_updateRegionHeader_unknownID_throwsRegionNotFound() async {
        let (client, _) = makeClient(now: fixedNow)
        let missingID = UUID()

        do {
            _ = try await client.updateRegionHeader(missingID, "x")
            XCTFail("Expected regionNotFound")
        } catch let error as NotebookClientError {
            XCTAssertEqual(error, .regionNotFound(missingID))
        } catch {
            XCTFail("Expected NotebookClientError, got \(error)")
        }
    }

    // MARK: - updateRegionLink

    @MainActor
    func test_updateRegionLink_external_setsURL() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)
        let created = try await client.addRegion(pageID, .zero, nil, nil)

        let url = URL(string: "https://example.com/x")!
        let snap = try await client.updateRegionLink(created.id, .external(url))

        XCTAssertEqual(snap.linkDestination, .external(url))
        let ctx = modelContext.context()
        let region = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<NoteRegion>()).first { $0.id == created.id }
        )
        XCTAssertEqual(region.linkExternalURL, url.absoluteString)
    }

    /// Walks every initial → next transition across the four
    /// destination kinds and asserts the union remains exclusive:
    /// exactly one of `linkExternalURL` / `linkTargetPageID` /
    /// `linkTargetNotebookID` / `linkTargetPDFID` is non-nil after
    /// the update, and it matches the new destination. Catches the
    /// failure mode where one transition would leave the prior
    /// kind's field set, causing the snapshot resolver to pick the
    /// wrong destination on re-read.
    @MainActor
    func test_updateRegionLink_unionStaysExclusiveAcrossTransitions() async throws {
        let externalURL = URL(string: "https://example.com")!
        let pageTargetID = UUID()
        let notebookTargetID = UUID()
        let pdfTargetID = UUID()

        let transitions: [(NoteRegionLinkDestination, NoteRegionLinkDestination)] = [
            (.page(pageTargetID),       .external(externalURL)),
            (.notebook(notebookTargetID), .pdf(pdfTargetID)),
            (.pdf(pdfTargetID),         .page(pageTargetID)),
            (.external(externalURL),    .notebook(notebookTargetID)),
        ]

        for (initial, next) in transitions {
            let (client, modelContext) = makeClient(now: fixedNow)
            let (_, pageID) = try seedNotebookPage(context: modelContext)
            let created = try await client.addRegion(pageID, .zero, nil, initial)

            _ = try await client.updateRegionLink(created.id, next)

            let ctx = modelContext.context()
            let region = try XCTUnwrap(
                try ctx.fetch(FetchDescriptor<NoteRegion>()).first { $0.id == created.id }
            )
            let nonNilCount = [
                region.linkExternalURL != nil,
                region.linkTargetPageID != nil,
                region.linkTargetNotebookID != nil,
                region.linkTargetPDFID != nil,
            ].filter { $0 }.count
            XCTAssertEqual(
                nonNilCount, 1,
                "Transition \(initial) → \(next) left \(nonNilCount) target fields set"
            )

            switch next {
            case .external(let url):
                XCTAssertEqual(region.linkExternalURL, url.absoluteString)
            case .page(let id):
                XCTAssertEqual(region.linkTargetPageID, id)
            case .notebook(let id):
                XCTAssertEqual(region.linkTargetNotebookID, id)
            case .pdf(let id):
                XCTAssertEqual(region.linkTargetPDFID, id)
            case .none, .broken:
                XCTFail("Test transition generator should not produce .none / .broken")
            }
        }
    }

    @MainActor
    func test_updateRegionLink_nil_clearsAllTargets() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)
        let url = URL(string: "https://example.com")!
        let created = try await client.addRegion(
            pageID, .zero, nil, .external(url)
        )

        let snap = try await client.updateRegionLink(created.id, nil)

        XCTAssertEqual(snap.linkDestination, .none)
        let ctx = modelContext.context()
        let region = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<NoteRegion>()).first { $0.id == created.id }
        )
        XCTAssertNil(region.linkExternalURL)
        XCTAssertNil(region.linkTargetPageID)
        XCTAssertNil(region.linkTargetNotebookID)
        XCTAssertNil(region.linkTargetPDFID)
    }

    @MainActor
    func test_updateRegionLink_unknownID_throwsRegionNotFound() async {
        let (client, _) = makeClient(now: fixedNow)
        let missingID = UUID()

        do {
            _ = try await client.updateRegionLink(
                missingID,
                .external(URL(string: "https://example.com")!)
            )
            XCTFail("Expected regionNotFound")
        } catch let error as NotebookClientError {
            XCTAssertEqual(error, .regionNotFound(missingID))
        } catch {
            XCTFail("Expected NotebookClientError, got \(error)")
        }
    }

    // MARK: - deleteRegion

    @MainActor
    func test_deleteRegion_removesRow_andBumpsNotebookModifiedAt() async throws {
        let (setupClient, modelContext) = makeClient(now: earlier)
        let (notebookID, pageID) = try seedNotebookPage(context: modelContext)
        let created = try await setupClient.addRegion(
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10), "Old", nil
        )

        let (exerciseClient, _) = makeClient(on: modelContext, now: fixedNow)
        try await exerciseClient.deleteRegion(created.id)

        let ctx = modelContext.context()
        let remaining = try ctx.fetch(FetchDescriptor<NoteRegion>())
        XCTAssertTrue(
            remaining.allSatisfy { $0.id != created.id },
            "Deleted region should not be in the store"
        )
        let notebook = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<Notebook>()).first { $0.id == notebookID }
        )
        XCTAssertEqual(notebook.modifiedAt, fixedNow,
                       "deleteRegion must bump the parent notebook's modifiedAt")
    }

    @MainActor
    func test_deleteRegion_unknownID_throwsRegionNotFound() async {
        let (client, _) = makeClient(now: fixedNow)
        let missingID = UUID()

        do {
            try await client.deleteRegion(missingID)
            XCTFail("Expected regionNotFound")
        } catch let error as NotebookClientError {
            XCTAssertEqual(error, .regionNotFound(missingID))
        } catch {
            XCTFail("Expected NotebookClientError, got \(error)")
        }
    }
}
