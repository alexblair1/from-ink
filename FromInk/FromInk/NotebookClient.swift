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
    var createNotebook: @Sendable (_ title: String, _ folderID: UUID?, _ kind: DocumentKind) async throws -> NotebookSnapshot
    var renameNotebook: @Sendable (_ id: UUID, _ title: String) async throws -> Void
    var deleteNotebook: @Sendable (_ id: UUID) async throws -> Void
    var touchNotebookModified: @Sendable (_ id: UUID) async throws -> Void

    // MARK: - Page lifecycle
    var createPage: @Sendable (_ notebookID: UUID, _ templateName: String) async throws -> NotePageSnapshot
    var deletePage: @Sendable (_ pageID: UUID) async throws -> Void
    var reindexPages: @Sendable (_ notebookID: UUID, _ orderedPageIDs: [UUID]) async throws -> Void
    var transferPage: @Sendable (_ pageID: UUID, _ destNotebookID: UUID, _ index: Int) async throws -> Void

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

    // MARK: - Folders / Tags
    var createFolder: @Sendable (_ name: String, _ parentID: UUID?) async throws -> FolderSnapshot
    var deleteFolder: @Sendable (_ id: UUID) async throws -> Void
    var moveNotebookToFolder: @Sendable (_ notebookID: UUID, _ folderID: UUID?) async throws -> Void
    var createTag: @Sendable (_ name: String, _ colorHex: String) async throws -> TagSnapshot
    var addTagToNotebook: @Sendable (_ tagID: UUID, _ notebookID: UUID) async throws -> Void
    var removeTagFromNotebook: @Sendable (_ tagID: UUID, _ notebookID: UUID) async throws -> Void
}

/// Caller-facing draft of a `NoteHistoryEntry`. The `NotebookClient`
/// translates this into the right `kind`-discriminated flat-field write
/// at the persistence layer. EventKit-driven history rows (event /
/// reminder kinds) bypass this draft and are written by a separate
/// EventKit observation pipeline (out of scope for this PR).
struct NoteHistoryDraft: Sendable, Equatable {
    var kind: HistoryKind
    var taskTitle: String = ""
    var taskDestination: String = ""           // Integration.rawValue
    var taskDestinationURL: String = ""
    var taskEventKitIdentifier: String?

    init(
        kind: HistoryKind,
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

// MARK: - Errors

enum NotebookClientError: Error, Equatable, Sendable {
    case notebookNotFound(UUID)
    case pageNotFound(UUID)
    case headerNotFound(UUID)
    case linkNotFound(UUID)
    case folderNotFound(UUID)
    case tagNotFound(UUID)
    case historyEntryNotFound(UUID)
}

// MARK: - DependencyKey

extension NotebookClient: DependencyKey {
    /// Fallback — every closure throws. The real client is constructed
    /// in `AppDependencyContainer` and installed via `install(into:)`.
    static let liveValue: NotebookClient = .throwing
    static let testValue: NotebookClient = .throwing

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
        createPage: { _, _ in throw CancellationError() },
        deletePage: { _ in throw CancellationError() },
        reindexPages: { _, _ in throw CancellationError() },
        transferPage: { _, _, _ in throw CancellationError() },
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
