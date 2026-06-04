import Foundation
import SwiftData

/// A persistent association between an EventKit calendar item (event or
/// reminder) and a From Ink `Notebook`. Powers the "tap an event row in
/// the brief and open its notebook" affordance.
///
/// Storage model: links are owned by `CalendarItemLink` rather than fields
/// on `Notebook`. One notebook can be linked to many events (a recurring
/// standup notebook collecting every occurrence); one event identifier
/// resolves to at most one notebook (1:1 enforced in service logic, not by
/// `@Attribute(.unique)` — CloudKit forbids unique constraints).
///
/// **CloudKit notes:**
/// - Every property has a default. Missing defaults cause silent sync
///   failures in production (see `data_model_edd.md` §3.2).
/// - All relationships optional. `@Relationship(...)` is declared on the
///   parent (`Notebook.calendarLinks`); this child holds the plain
///   back-pointer with no macro — matches the `NotePage` / `Tag` pattern
///   to dodge SwiftData's "duplicate inverse" runtime error.
/// - `pageID` is a plain `UUID?` rather than a `NotePage?` relationship.
///   When a page is deleted the link falls through to "last edited page"
///   at navigation time, so a relationship-with-nullify would buy us
///   nothing extra and would require adding an inverse on `NotePage`.
///
/// **Recurring events:** EventKit shares one `eventIdentifier` across all
/// occurrences of a recurring event, so a single `CalendarItemLink` row
/// naturally covers the whole series. We do NOT store an occurrence date
/// — per-occurrence linking is explicitly out of scope (the recurring
/// standup is one notebook, not 52).
///
/// **Identifier strategy:** EventKit identifiers can become stale —
/// `localIdentifier` is invalidated when the user moves the event to a
/// different calendar or restores from a backup. `externalIdentifier`
/// (the iCloud / CalDAV stable ID) survives those transitions. The
/// validator resolves by local first, then external, and rewrites
/// `localIdentifier` when external lookup finds a record under a new
/// local ID — so the link keeps working without user intervention.
///
@Model final class CalendarItemLink {
    var id: UUID = UUID()

    /// `EKEvent.eventIdentifier` for events, `EKCalendarItem.calendarItemIdentifier`
    /// for reminders. Stable per-device under normal conditions; may
    /// change when the item is moved between calendars or restored from
    /// backup. The validator updates this field via `externalIdentifier`
    /// fallback when EventKit no longer recognizes the local value.
    var localIdentifier: String = ""

    /// `EKCalendarItem.calendarItemExternalIdentifier`. Syncs across
    /// devices via iCloud / CalDAV. `nil` for purely local calendars
    /// (e.g., the on-device "On My iPhone" calendar). Used as the
    /// failover when `localIdentifier` lookup returns nil.
    var externalIdentifier: String? = nil

    var kindRaw: String = CalendarItemKind.event.rawValue
    var kind: CalendarItemKind {
        get { CalendarItemKind(rawValue: kindRaw) ?? .event }
        set { kindRaw = newValue.rawValue }
    }

    var sourceRaw: String = CalendarItemLinkSource.linked.rawValue
    var source: CalendarItemLinkSource {
        get { CalendarItemLinkSource(rawValue: sourceRaw) ?? .linked }
        set { sourceRaw = newValue.rawValue }
    }

    /// Inverse declared on `Notebook.calendarLinks`. Cascade-delete from
    /// the notebook side means deleting a notebook removes its link
    /// records; deleting a link never touches the notebook. The validator
    /// relies on this asymmetry — see `CalendarItemLinkValidator`.
    var notebook: Notebook? = nil

    /// Plain `UUID?` reference to a `NotePage`. `nil` means "open the
    /// last-edited page" at navigation time. Plain reference rather than
    /// a SwiftData relationship so a deleted page degrades to the
    /// fallback without dragging in an inverse on `NotePage`.
    var pageID: UUID? = nil

    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        localIdentifier: String,
        externalIdentifier: String? = nil,
        kind: CalendarItemKind,
        source: CalendarItemLinkSource,
        notebook: Notebook? = nil,
        pageID: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.externalIdentifier = externalIdentifier
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.notebook = notebook
        self.pageID = pageID
        self.createdAt = createdAt
    }
}

// MARK: - Enums

enum CalendarItemKind: String, Sendable {
    case event
    case reminder
}

enum CalendarItemLinkSource: String, Sendable {
    /// User tapped "Create notebook from event/reminder" on an unlinked
    /// brief row. The notebook was minted by the link flow.
    case createdFromItem

    /// User tapped "Link to existing" and selected a pre-existing notebook.
    case linked
}

// MARK: - Snapshot

extension CalendarItemLink {
    /// Sendable value-type view of a `CalendarItemLink`. `@Model` objects
    /// don't enter TCA `State` (per the data model EDD); reducers and
    /// adapters consume this snapshot instead.
    ///
    /// `notebookID` carries the destination so navigation can resolve
    /// the target without touching the link's managed object graph.
    /// `notebookTitle` is denormalized for the action-sheet copy
    /// ("Open notebook: ___") so we don't fetch the Notebook a second
    /// time at adapter resolution.
    struct Snapshot: Equatable, Sendable {
        let id: UUID
        let localIdentifier: String
        let externalIdentifier: String?
        let kind: CalendarItemKind
        let source: CalendarItemLinkSource
        let notebookID: UUID?
        let notebookTitle: String
        let pageID: UUID?
        let createdAt: Date
    }

    /// Build a snapshot from the persistent model. Reads notebook title
    /// once at snapshot time — callers iterate over the snapshot, not
    /// the @Model, so the snapshot must carry everything the adapter
    /// needs to render without re-touching the context.
    var snapshot: Snapshot {
        Snapshot(
            id: id,
            localIdentifier: localIdentifier,
            externalIdentifier: externalIdentifier,
            kind: kind,
            source: source,
            notebookID: notebook?.id,
            notebookTitle: notebook?.title ?? "",
            pageID: pageID,
            createdAt: createdAt
        )
    }
}
