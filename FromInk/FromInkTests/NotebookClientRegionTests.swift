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
            _ = try await client.addRegion(missingID, .zero, nil, nil, nil, nil)
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
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10), nil, nil, nil, nil
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
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10), "Old", nil, nil, nil
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
            pageID, .zero, "Old", nil, nil, nil
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
        let created = try await client.addRegion(pageID, .zero, nil, nil, nil, nil)

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
            let created = try await client.addRegion(pageID, .zero, nil, nil, initial, nil)

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
            pageID, .zero, nil, nil, .external(url), nil
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
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10), "Old", nil, nil, nil
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

    // MARK: - linkRecognizedText and eventKitIdentifier (header/link/event
    //         independence)

    /// Round-trip: persist a region with `linkRecognizedText` and
    /// `eventKitIdentifier` set, then verify both surface on the
    /// snapshot after a fresh re-read from the store. The fields are
    /// optional and read-back independently of all other associations.
    @MainActor
    func test_addRegion_persistsLinkRecognizedTextAndEventKitIdentifier() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)

        let created = try await client.addRegion(
            pageID, .zero,
            nil,
            "near-this-link text",
            .external(URL(string: "https://example.com")!),
            "EK-12345"
        )

        XCTAssertEqual(created.linkRecognizedText, "near-this-link text")
        XCTAssertEqual(created.eventKitIdentifier, "EK-12345")
        XCTAssertNil(created.headerOCRText)

        let ctx = modelContext.context()
        let region = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<NoteRegion>()).first { $0.id == created.id }
        )
        XCTAssertEqual(region.linkRecognizedText, "near-this-link text")
        XCTAssertEqual(region.eventKitIdentifier, "EK-12345")
        XCTAssertNil(region.headerOCRText)
    }

    /// The snapshot collapses empty `linkRecognizedText` to nil so the
    /// dispatch panel's link row doesn't render an empty recognized-text
    /// label and `hasAnyAssociation` doesn't keep a phantom association
    /// alive. Same empty-string-to-nil rule as `headerOCRText`.
    @MainActor
    func test_snapshot_emptyLinkRecognizedText_collapsesToNil() async throws {
        let (_, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)
        let ctx = modelContext.context()
        let page = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<NotePage>()).first { $0.id == pageID }
        )

        // Bypass the API so we can plant the empty string the API
        // wouldn't normally let through — exercising the snapshot
        // normalization itself.
        let region = NoteRegion(
            page: page,
            rect: .zero,
            createdAt: fixedNow,
            linkRecognizedText: ""
        )
        ctx.insert(region)
        try ctx.save()

        let snap = NoteRegionSnapshot(model: region)
        XCTAssertNil(snap.linkRecognizedText)
    }

    /// Same empty-string-to-nil normalization as above, applied to the
    /// `eventKitIdentifier` field. An empty EK identifier would surface
    /// the calendar badge for a region that doesn't actually anchor an
    /// event; collapsing to nil keeps the badge gated on real intent.
    @MainActor
    func test_snapshot_emptyEventKitIdentifier_collapsesToNil() async throws {
        let (_, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)
        let ctx = modelContext.context()
        let page = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<NotePage>()).first { $0.id == pageID }
        )

        let region = NoteRegion(
            page: page,
            rect: .zero,
            createdAt: fixedNow,
            eventKitIdentifier: ""
        )
        ctx.insert(region)
        try ctx.save()

        let snap = NoteRegionSnapshot(model: region)
        XCTAssertNil(snap.eventKitIdentifier)
    }

    /// Load-bearing invariant for bug #5: writing `linkRecognizedText`
    /// must NOT mark the region as a header. The two fields are
    /// independent so that adding a link over the same handwriting
    /// the user already marked as a header doesn't produce a duplicate
    /// header row in the dispatch panel.
    @MainActor
    func test_addRegion_linkRecognizedText_doesNotMarkAsHeader() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)

        let created = try await client.addRegion(
            pageID, .zero,
            nil,
            "link label text",
            .external(URL(string: "https://example.com")!),
            nil
        )

        XCTAssertNil(
            created.headerOCRText,
            "Creating a link must not populate headerOCRText \u{2014} that would surface a phantom header row in the dispatch panel."
        )
        XCTAssertEqual(created.linkRecognizedText, "link label text")
        XCTAssertEqual(created.linkDestination, .external(URL(string: "https://example.com")!))
    }

    /// Inverse invariant: writing `headerOCRText` must NOT populate
    /// `linkRecognizedText`. A header with no link should have a nil
    /// `linkRecognizedText` so it doesn't surface in the links tab.
    @MainActor
    func test_addRegion_headerOCRText_doesNotPopulateLinkRecognizedText() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)

        let created = try await client.addRegion(
            pageID, .zero,
            "Section heading",
            nil,
            nil,
            nil
        )

        XCTAssertEqual(created.headerOCRText, "Section heading")
        XCTAssertNil(created.linkRecognizedText)
        XCTAssertEqual(created.linkDestination, .none)
    }

    /// A region can carry header + link + event simultaneously and
    /// each field surfaces independently. Verifies the at-most-one-per-
    /// kind invariant on the API boundary doesn't accidentally collapse
    /// cross-kind associations.
    @MainActor
    func test_addRegion_allThreeAssociations_persistIndependently() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)

        let url = URL(string: "https://example.com")!
        let created = try await client.addRegion(
            pageID, CGRect(x: 0, y: 0, width: 10, height: 10),
            "Section",
            "link label",
            .external(url),
            "EK-12345"
        )

        XCTAssertEqual(created.headerOCRText, "Section")
        XCTAssertEqual(created.linkRecognizedText, "link label")
        XCTAssertEqual(created.linkDestination, .external(url))
        XCTAssertEqual(created.eventKitIdentifier, "EK-12345")
        XCTAssertTrue(created.hasAnyAssociation)
    }

    /// `hasAnyAssociation` returns true when only `eventKitIdentifier`
    /// is set — the calendar badge must keep a region alive even when
    /// the user marks an event without also adding a header or link.
    @MainActor
    func test_hasAnyAssociation_trueForEventOnlyRegion() async throws {
        let (client, modelContext) = makeClient(now: fixedNow)
        let (_, pageID) = try seedNotebookPage(context: modelContext)

        let created = try await client.addRegion(
            pageID, .zero, nil, nil, nil, "EK-only"
        )

        XCTAssertNil(created.headerOCRText)
        XCTAssertNil(created.linkRecognizedText)
        XCTAssertEqual(created.linkDestination, .none)
        XCTAssertEqual(created.eventKitIdentifier, "EK-only")
        XCTAssertTrue(
            created.hasAnyAssociation,
            "An event-only region must report hasAnyAssociation == true so the indicator renders."
        )
    }
}
