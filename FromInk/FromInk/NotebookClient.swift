import ComposableArchitecture
import CoreGraphics
import Foundation

/// TCA dependency providing all notebook / page / header / link / history
/// persistence operations. The single chokepoint for SwiftData writes in
/// the notebook domain — reducers never touch `ModelContext` directly,
/// and never construct relationship graphs themselves.
///
/// **Granularity rationale:** thick verbs (`transferPage`,
/// `recordHistory`, `addLink`) rather than CRUD-per-model because
/// SwiftData relationship integrity (parent reassignment, sibling
/// reindex, atomic save) is domain logic that should not leak into
/// reducer effects. The thick client is harder to misuse.
///
/// **Snapshot lifecycle:** every closure that reads SwiftData converts
/// `@Model` objects into `Sendable` snapshot value types before crossing
/// the actor boundary back to the caller. `@Model` instances never enter
/// TCA `State` (per `view_layer_edd.md` §15).
///
/// **Method categories** (in order of appearance):
///   1. Reads — fetch + projection.
///   2. Notebook lifecycle — create / rename / delete / touch.
///   3. PDF lookups + import — `fetchAllPDFs`, `fetchRecentPDFs`,
///      `findPDFByContentHash`, `importPDF`. Defense-in-depth dedup
///      lives inside `importPDF`; callers don't have to remember.
///   4. Page lifecycle.
///   5. Page content (high frequency — drawing / OCR / typed text).
///   6. Headers / Links / History.
///   7. Folders / Tags.
struct NotebookClient: Sendable {
    // MARK: - Reads
    var fetchAllNotebooks: @Sendable () async throws -> [NotebookSnapshot]
    var fetchNotebook: @Sendable (UUID) async throws -> NotebookDetailSnapshot?
    var fetchPage: @Sendable (UUID) async throws -> NotePageDetailSnapshot?
    var fetchPagesForNotebook: @Sendable (UUID) async throws -> [NotePageSnapshot]
    var fetchAllFolders: @Sendable () async throws -> [FolderSnapshot]
    var fetchHistoryForPage: @Sendable (UUID) async throws -> [NoteHistoryEntrySnapshot]
    var fetchHistoryForNotebook: @Sendable (UUID) async throws -> [NoteHistoryEntrySnapshot]
    var fetchAllTags: @Sendable () async throws -> [TagSnapshot]

    // MARK: - Notebook lifecycle
    var createNotebook: @Sendable (_ title: String, _ folderID: UUID?, _ type: NotebookType) async throws -> NotebookSnapshot
    var renameNotebook: @Sendable (_ id: UUID, _ title: String) async throws -> Void
    var deleteNotebook: @Sendable (_ id: UUID) async throws -> Void
    var touchNotebookModified: @Sendable (_ id: UUID) async throws -> Void

    // MARK: - PDF lookups + lifecycle
    /// All PDFs, newest-modified first.
    var fetchAllPDFs: @Sendable () async throws -> [ImportedPDFSnapshot]
    /// Most-recently-opened PDFs, falling back to `modifiedAt` for
    /// never-opened ones. Drives the home "Recent PDFs" section.
    var fetchRecentPDFs: @Sendable (_ limit: Int) async throws -> [ImportedPDFSnapshot]
    /// Looks up a PDF by id. O(1) — backs the dedup-recover path in
    /// `LibraryFeature` and the viewer's load step. Returns nil when
    /// the row no longer exists (e.g., delete race after a dedup hit).
    var fetchPDF: @Sendable (_ id: UUID) async throws -> ImportedPDFSnapshot?
    /// Loads the persisted PDF bytes for a given id. Separated from
    /// `fetchPDF` so list views never accidentally materialize the
    /// externalStorage blob — only the viewer asks for the bytes.
    /// Returns nil when the row no longer exists OR when
    /// `sourcePDFData` is somehow nil (corrupted import).
    var fetchPDFData: @Sendable (_ id: UUID) async throws -> Data?
    /// Looks up an existing PDF by content hash. Used by the import
    /// flow to detect a re-import of the same bytes and surface the
    /// existing PDF instead of inserting a duplicate.
    var findPDFByContentHash: @Sendable (_ hash: String) async throws -> ImportedPDFSnapshot?
    /// Inserts a new `ImportedPDF` from a finished import draft. The
    /// caller (`ImportPDFService`) is responsible for picking, hashing,
    /// metadata extraction, and the size guard before this is invoked.
    /// Throws `NotebookClientError.pdfAlreadyImported(existingID:)` if
    /// the content hash matches an already-imported PDF — caller is
    /// expected to navigate to the existing snapshot instead.
    var importPDF: @Sendable (_ draft: ImportedPDFDraft, _ folderID: UUID?) async throws -> ImportedPDFSnapshot
    /// Stamps `lastOpenedAt` on the PDF. Coalesced — skips the write
    /// (and the resulting cross-device sync ping) if the stored value
    /// is already within the 5-minute coalesce window.
    var touchPDFOpened: @Sendable (_ id: UUID) async throws -> Void

    // MARK: - Page lifecycle
    var createPage: @Sendable (_ notebookID: UUID, _ templateName: String) async throws -> NotePageSnapshot
    var deletePage: @Sendable (_ pageID: UUID) async throws -> Void
    var reindexPages: @Sendable (_ notebookID: UUID, _ orderedPageIDs: [UUID]) async throws -> Void
    var transferPage: @Sendable (_ pageID: UUID, _ destNotebookID: UUID, _ index: Int) async throws -> Void
    /// Persists a per-page template choice. Returns the refreshed
    /// snapshot so the reducer can update its in-memory pages array
    /// without round-tripping through the store-change observer.
    /// Bumps `modifiedAt` on both the page and its parent notebook.
    var setPageTemplate: @Sendable (_ pageID: UUID, _ templateName: String) async throws -> NotePageSnapshot

    // MARK: - Page content (high frequency)
    /// Persists pre-encoded ink data. The Coordinator owns the
    /// `PKDrawing.dataRepresentation()` translation before crossing this
    /// boundary — `PKDrawing` is intentionally absent from the dependency
    /// surface (per CLAUDE.md "Canvas + TCA boundary"). Updates
    /// `NotePage.modifiedAt` and bubbles to `Notebook.modifiedAt`.
    var saveDrawing: @Sendable (_ pageID: UUID, _ drawingData: Data, _ thumbnailData: Data?) async throws -> Void
    var updateOCR: @Sendable (_ pageID: UUID, _ text: String) async throws -> Void
    var updateTypedText: @Sendable (_ pageID: UUID, _ text: String) async throws -> Void

    // MARK: - Headers / Links / History
    var addHeader: @Sendable (_ pageID: UUID, _ rect: CGRect, _ ocrText: String) async throws -> NoteHeaderSnapshot
    var updateHeaderOCR: @Sendable (_ headerID: UUID, _ ocrText: String) async throws -> Void
    var deleteHeader: @Sendable (_ headerID: UUID) async throws -> Void
    var addLink: @Sendable (_ pageID: UUID, _ rect: CGRect, _ ocrText: String, _ destination: NoteLinkDestination) async throws -> NoteLinkSnapshot
    var updateLink: @Sendable (_ linkID: UUID, _ destination: NoteLinkDestination) async throws -> Void
    var deleteLink: @Sendable (_ linkID: UUID) async throws -> Void
    var recordHistory: @Sendable (_ pageID: UUID, _ entry: NoteHistoryDraft) async throws -> NoteHistoryEntrySnapshot
    var updateHistoryStatus: @Sendable (_ entryID: UUID, _ status: String) async throws -> Void

    // MARK: - Regions
    /// Create a new `NoteRegion` on the given page. Either or both
    /// associations may be supplied at creation time: pass
    /// `headerOCRText` for the bookmark/header path, pass
    /// `linkDestination` for the link path, pass both for a region
    /// that opens with two badges from the start. Both nil mints a
    /// region with no associations — useful for tests / edge cases
    /// but normally the user picks at least one in the lasso menu.
    var addRegion: @Sendable (
        _ pageID: UUID,
        _ rect: CGRect,
        _ headerOCRText: String?,
        _ linkDestination: NoteRegionLinkDestination?
    ) async throws -> NoteRegionSnapshot

    // MARK: - Folders / Tags
    var createFolder: @Sendable (_ name: String, _ parentID: UUID?) async throws -> FolderSnapshot
    var deleteFolder: @Sendable (_ id: UUID) async throws -> Void
    var moveNotebookToFolder: @Sendable (_ notebookID: UUID, _ folderID: UUID?) async throws -> Void
    var createTag: @Sendable (_ name: String, _ colorHex: String) async throws -> TagSnapshot
    var addTagToNotebook: @Sendable (_ tagID: UUID, _ notebookID: UUID) async throws -> Void
    var removeTagFromNotebook: @Sendable (_ tagID: UUID, _ notebookID: UUID) async throws -> Void
}

/// Caller-facing draft of a task-routed `NoteHistoryEntry`. The
/// `NotebookClient` translates this into the right flat-field write at
/// the persistence layer.
///
/// **Scope: task entries only.** `kind` is restricted to the `task_*`
/// cases because the draft only carries `task*` fields. EventKit-driven
/// history rows (`.event` / `.reminder` kinds) carry different fields
/// (event title + dates + calendar name; reminder title + due date) and
/// are written by a separate EventKit observation pipeline that doesn't
/// yet exist; when it lands it'll add `EventDraft` / `ReminderDraft`
/// types with the right field shape.
struct NoteHistoryDraft: Sendable, Equatable {
    /// Restricted `HistoryKind` covering only the task lifecycle —
    /// `.event` and `.reminder` are excluded so a degenerate draft
    /// (e.g., kind=.event but only task fields populated) can't compile.
    enum TaskKind: Sendable, Equatable {
        case routed
        case completed
        case deleted

        var historyKind: HistoryKind {
            switch self {
            case .routed:    return .taskRouted
            case .completed: return .taskCompleted
            case .deleted:   return .taskDeleted
            }
        }
    }

    var kind: TaskKind
    var taskTitle: String = ""
    var taskDestination: String = ""           // Integration.rawValue
    var taskDestinationURL: String = ""
    var taskEventKitIdentifier: String?

    init(
        kind: TaskKind,
        taskTitle: String = "",
        taskDestination: String = "",
        taskDestinationURL: String = "",
        taskEventKitIdentifier: String? = nil
    ) {
        self.kind = kind
        self.taskTitle = taskTitle
        self.taskDestination = taskDestination
        self.taskDestinationURL = taskDestinationURL
        self.taskEventKitIdentifier = taskEventKitIdentifier
    }
}

/// Caller-facing payload describing a PDF that has been picked, read,
/// hashed, and inspected — but not yet persisted. `ImportPDFService`
/// produces it; `NotebookClient.importPDF` inserts it.
///
/// The split exists so the side-effectful work (security-scoped URL
/// read, SHA-256, PDFKit parse, thumbnail render, size guard) lives
/// in a dependency that's straightforward to mock in tests, while
/// the SwiftData write stays in `NotebookClient` alongside all other
/// model writes.
struct ImportedPDFDraft: Sendable, Equatable {
    var title: String
    var contentHash: String        // SHA-256 hex of pdfData
    var pageCount: Int             // PDF page count

    /// Byte size of `pdfData`. Caller-maintained invariant:
    /// `byteSize == pdfData.count` at all times. Carried as a separate
    /// field (rather than computed from `pdfData.count` at the
    /// `importPDF` write site) so the value can be threaded through
    /// the size-guard pipeline without re-measuring; the `Data` count
    /// is O(1) but the field is the source of truth for the persisted
    /// `Notebook.byteSize`. Any future code that mutates `pdfData`
    /// without updating `byteSize` will silently corrupt the size
    /// indicator across the library UI.
    var byteSize: Int
    var pdfData: Data              // the actual bytes; promoted to CKAsset on sync
    var thumbnailData: Data?       // rendered first page, JPEG ~0.7 quality

    init(
        title: String,
        contentHash: String,
        pageCount: Int,
        byteSize: Int,
        pdfData: Data,
        thumbnailData: Data? = nil
    ) {
        self.title = title
        self.contentHash = contentHash
        self.pageCount = pageCount
        self.byteSize = byteSize
        self.pdfData = pdfData
        self.thumbnailData = thumbnailData
    }
}

// MARK: - Errors

enum NotebookClientError: Error, Equatable, Sendable {
    case notebookNotFound(UUID)
    case pageNotFound(UUID)
    case headerNotFound(UUID)
    case linkNotFound(UUID)
    case folderNotFound(UUID)
    case tagNotFound(UUID)
    case historyEntryNotFound(UUID)
    /// Defense-in-depth dedup: a PDF with this `contentHash` already
    /// exists. Returned by `importPDF` so the caller can navigate to the
    /// existing notebook instead of silently inserting a duplicate.
    /// `existingID` is the already-imported `Notebook.id`.
    case pdfAlreadyImported(existingID: UUID)
}

// MARK: - Tunables

extension NotebookClient {
    /// `touchPDFOpened` skips the write (and the resulting cross-device
    /// sync ping) if the stored value is already within this many
    /// seconds of `now`. 5 minutes matches the iOS Notes convention
    /// for "Recently Opened" semantics.
    static let openedCoalesceWindow: TimeInterval = 300
}

// MARK: - DependencyKey

extension NotebookClient: DependencyKey {
    /// Fallback — every closure throws. The real client is constructed
    /// in `AppDependencyContainer` and installed via `install(into:)`.
    static let liveValue: NotebookClient = .throwing

    /// In-memory client for TestStore tests. Backed by a fresh
    /// `SyncedModelContextDependency.inMemory()` container per access,
    /// so reducer tests get a clean store without explicit setup.
    /// Overrideable per-test via `withDependencies { $0.notebookClient = ... }`.
    static var testValue: NotebookClient {
        .live(
            modelContext: .inMemory(),
            calendarContext: .testValue
        )
    }

    /// Convenience: every closure throws `CancellationError`. Useful as
    /// a base for test customization with `withDependencies { ... }`.
    static let throwing: NotebookClient = NotebookClient(
        fetchAllNotebooks: { throw CancellationError() },
        fetchNotebook: { _ in throw CancellationError() },
        fetchPage: { _ in throw CancellationError() },
        fetchPagesForNotebook: { _ in throw CancellationError() },
        fetchAllFolders: { throw CancellationError() },
        fetchHistoryForPage: { _ in throw CancellationError() },
        fetchHistoryForNotebook: { _ in throw CancellationError() },
        fetchAllTags: { throw CancellationError() },
        createNotebook: { _, _, _ in throw CancellationError() },
        renameNotebook: { _, _ in throw CancellationError() },
        deleteNotebook: { _ in throw CancellationError() },
        touchNotebookModified: { _ in throw CancellationError() },
        fetchAllPDFs: { throw CancellationError() },
        fetchRecentPDFs: { _ in throw CancellationError() },
        fetchPDF: { _ in throw CancellationError() },
        fetchPDFData: { _ in throw CancellationError() },
        findPDFByContentHash: { _ in throw CancellationError() },
        importPDF: { _, _ in throw CancellationError() },
        touchPDFOpened: { _ in throw CancellationError() },
        createPage: { _, _ in throw CancellationError() },
        deletePage: { _ in throw CancellationError() },
        reindexPages: { _, _ in throw CancellationError() },
        transferPage: { _, _, _ in throw CancellationError() },
        setPageTemplate: { _, _ in throw CancellationError() },
        saveDrawing: { _, _, _ in throw CancellationError() },
        updateOCR: { _, _ in throw CancellationError() },
        updateTypedText: { _, _ in throw CancellationError() },
        addHeader: { _, _, _ in throw CancellationError() },
        updateHeaderOCR: { _, _ in throw CancellationError() },
        deleteHeader: { _ in throw CancellationError() },
        addLink: { _, _, _, _ in throw CancellationError() },
        updateLink: { _, _ in throw CancellationError() },
        deleteLink: { _ in throw CancellationError() },
        recordHistory: { _, _ in throw CancellationError() },
        updateHistoryStatus: { _, _ in throw CancellationError() },
        addRegion: { _, _, _, _ in throw CancellationError() },
        createFolder: { _, _ in throw CancellationError() },
        deleteFolder: { _ in throw CancellationError() },
        moveNotebookToFolder: { _, _ in throw CancellationError() },
        createTag: { _, _ in throw CancellationError() },
        addTagToNotebook: { _, _ in throw CancellationError() },
        removeTagFromNotebook: { _, _ in throw CancellationError() }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var notebookClient: NotebookClient {
        get { self[NotebookClient.self] }
        set { self[NotebookClient.self] = newValue }
    }
}
