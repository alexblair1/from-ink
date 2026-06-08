import ComposableArchitecture
import CoreGraphics
import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.fromink.app", category: "NotebookClient")

extension NotebookClient {
    /// Constructs the live client. Called from `AppDependencyContainer`;
    /// every closure hops to `@MainActor` to touch `ModelContext` and
    /// returns `Sendable` snapshots — `@Model` instances never escape
    /// the MainActor boundary.
    ///
    /// All mutations call `try ctx.save()` so the
    /// `NSManagedObjectContextDidSave` notification fires and downstream
    /// reducer observations (`LibraryFeature`, `DispatchPanelFeature`)
    /// refresh. Bypassing `save()` would silently break the @Query
    /// replacement pipeline.
    static func live(
        modelContext: SyncedModelContextDependency,
        calendarContext: CalendarContext
    ) -> NotebookClient {
        NotebookClient(
            // MARK: - Reads
            fetchAllNotebooks: {
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<Notebook>(
                        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                    )
                    return try ctx.fetch(descriptor).map(NotebookSnapshot.init(model:))
                }
            },
            fetchNotebook: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    return try fetchNotebookModel(id: id, ctx: ctx).map(NotebookDetailSnapshot.init(model:))
                }
            },
            fetchPage: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    return try fetchPageModel(id: id, ctx: ctx).map(NotePageDetailSnapshot.init(model:))
                }
            },
            fetchPagesForNotebook: { notebookID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else { return [] }
                    return (nb.pages ?? [])
                        .sorted { $0.index < $1.index }
                        .map(NotePageSnapshot.init(model:))
                }
            },
            fetchAllFolders: {
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<Folder>(
                        sortBy: [SortDescriptor(\.sortOrder)]
                    )
                    return try ctx.fetch(descriptor).map(FolderSnapshot.init(model:))
                }
            },
            fetchHistoryForPage: { pageID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else { return [] }
                    return (page.history ?? [])
                        .sorted { $0.timestamp > $1.timestamp }
                        .map(NoteHistoryEntrySnapshot.init(model:))
                }
            },
            fetchHistoryForNotebook: { notebookID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else { return [] }
                    return (nb.pages ?? [])
                        .flatMap { $0.history ?? [] }
                        .sorted { $0.timestamp > $1.timestamp }
                        .map(NoteHistoryEntrySnapshot.init(model:))
                }
            },
            fetchAllTags: {
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<Tag>(
                        sortBy: [SortDescriptor(\.createdAt)]
                    )
                    return try ctx.fetch(descriptor).map(TagSnapshot.init(model:))
                }
            },

            // MARK: - Notebook lifecycle
            createNotebook: { title, folderID, type in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let folder: Folder?
                    if let folderID {
                        folder = try fetchFolderModel(id: folderID, ctx: ctx)
                        if folder == nil { throw NotebookClientError.folderNotFound(folderID) }
                    } else {
                        folder = nil
                    }
                    let now = calendarContext.now()
                    let nb = Notebook(
                        title: title,
                        createdAt: now,
                        modifiedAt: now,
                        type: type,
                        folder: folder
                    )
                    ctx.insert(nb)
                    try ctx.save()
                    return NotebookSnapshot(model: nb)
                }
            },
            renameNotebook: { id, title in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: id, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(id)
                    }
                    nb.title = title
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },
            deleteNotebook: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: id, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(id)
                    }
                    ctx.delete(nb)   // cascades to pages → headers/links/history
                    try ctx.save()
                }
            },
            touchNotebookModified: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: id, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(id)
                    }
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },

            // MARK: - PDF lookups + lifecycle
            fetchAllPDFs: {
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<ImportedPDF>(
                        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                    )
                    return try ctx.fetch(descriptor).map(ImportedPDFSnapshot.init(model:))
                }
            },
            fetchRecentPDFs: { limit in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    // SwiftData's SortDescriptor doesn't compose a
                    // nullable-fallback ordering ("lastOpenedAt ??
                    // modifiedAt"). Approximate with two predicate-
                    // narrowed, store-side-limited fetches:
                    //   1) opened PDFs, sorted by lastOpenedAt desc
                    //   2) never-opened PDFs (lastOpenedAt nil),
                    //      sorted by modifiedAt desc — only if we got
                    //      fewer than `limit` in step 1
                    // Bounds memory to ~2·limit even at huge library
                    // sizes.
                    var opened = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.lastOpenedAt != nil },
                        sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
                    )
                    opened.fetchLimit = limit
                    let openedRows = try ctx.fetch(opened)

                    if openedRows.count >= limit {
                        return openedRows.map(ImportedPDFSnapshot.init(model:))
                    }
                    var neverOpened = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.lastOpenedAt == nil },
                        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                    )
                    neverOpened.fetchLimit = limit - openedRows.count
                    let neverOpenedRows = try ctx.fetch(neverOpened)
                    return (openedRows + neverOpenedRows).map(ImportedPDFSnapshot.init(model:))
                }
            },
            fetchPDF: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.id == id }
                    )
                    return try ctx.fetch(descriptor).first.map(ImportedPDFSnapshot.init(model:))
                }
            },
            fetchPDFData: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.id == id }
                    )
                    // Reading `sourcePDFData` materializes the
                    // externalStorage blob synchronously — for
                    // hundreds-of-MB PDFs this is a real MainActor
                    // I/O block (sub-second on local SSD, multi-second
                    // on cold iCloud). `ModelContext` is MainActor-
                    // bound, so we can't easily move the read off-
                    // actor. The viewer's spinner is up for this
                    // entire window; the dominant cost — PDFKit's
                    // parse — runs off-actor inside `PDFContent`
                    // (see `PDFCanvas.swift`).
                    return try ctx.fetch(descriptor).first?.sourcePDFData
                }
            },
            findPDFByContentHash: { hash in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.contentHash == hash }
                    )
                    return try ctx.fetch(descriptor).first.map(ImportedPDFSnapshot.init(model:))
                }
            },
            importPDF: { draft, folderID in
                try await MainActor.run {
                    let ctx = modelContext.context()

                    // Defense-in-depth dedup. Callers are expected to
                    // pre-check via findPDFByContentHash, but the moment
                    // there are two import sites (home button, share
                    // extension, drag-and-drop), one will forget — and
                    // CloudKit will faithfully replicate the duplicate
                    // to every device. Throwing here forces the caller
                    // to branch to navigate-to-existing instead.
                    let hash = draft.contentHash
                    let existingDescriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.contentHash == hash }
                    )
                    if let existing = try ctx.fetch(existingDescriptor).first {
                        throw NotebookClientError.pdfAlreadyImported(existingID: existing.id)
                    }

                    let folder: Folder?
                    if let folderID {
                        folder = try fetchFolderModel(id: folderID, ctx: ctx)
                        if folder == nil { throw NotebookClientError.folderNotFound(folderID) }
                    } else {
                        folder = nil
                    }
                    let now = calendarContext.now()
                    let pdf = ImportedPDF(
                        title: draft.title,
                        contentHash: draft.contentHash,
                        pageCount: draft.pageCount,
                        byteSize: draft.byteSize,
                        createdAt: now,
                        modifiedAt: now,
                        folder: folder
                    )
                    pdf.sourcePDFData = draft.pdfData
                    pdf.thumbnailData = draft.thumbnailData
                    // lastOpenedAt left nil; first open via touchPDFOpened
                    // bubbles it onto the Recent list.
                    ctx.insert(pdf)
                    try ctx.save()
                    log.info("Imported PDF id=\(pdf.id.uuidString, privacy: .public) hash=\(String(hash.prefix(8)), privacy: .public) bytes=\(draft.byteSize, privacy: .public) pages=\(draft.pageCount, privacy: .public)")
                    return ImportedPDFSnapshot(model: pdf)
                }
            },
            touchPDFOpened: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let descriptor = FetchDescriptor<ImportedPDF>(
                        predicate: #Predicate { $0.id == id }
                    )
                    guard let pdf = try ctx.fetch(descriptor).first else {
                        throw NotebookClientError.notebookNotFound(id)
                    }
                    let now = calendarContext.now()
                    if let last = pdf.lastOpenedAt,
                       now.timeIntervalSince(last) < NotebookClient.openedCoalesceWindow {
                        return
                    }
                    pdf.lastOpenedAt = now
                    try ctx.save()
                }
            },

            // MARK: - Page lifecycle
            createPage: { notebookID, templateName in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(notebookID)
                    }
                    let nextIndex = (nb.pages ?? []).map(\.index).max().map { $0 + 1 } ?? 0
                    let now = calendarContext.now()
                    let page = NotePage(
                        index: nextIndex,
                        createdAt: now,
                        templateName: templateName,
                        notebook: nb
                    )
                    ctx.insert(page)
                    nb.modifiedAt = now
                    try ctx.save()
                    return NotePageSnapshot(model: page)
                }
            },
            deletePage: { pageID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let parent = page.notebook
                    ctx.delete(page)   // cascades to headers/links/history
                    if let parent {
                        reindex(pages: parent.pages ?? [])
                        parent.modifiedAt = calendarContext.now()
                    }
                    try ctx.save()
                }
            },
            reindexPages: { notebookID, orderedPageIDs in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(notebookID)
                    }
                    let pageByID = Dictionary(uniqueKeysWithValues: (nb.pages ?? []).map { ($0.id, $0) })
                    // Validate orderedPageIDs covers exactly the notebook's
                    // current page set — caller must not pass stale or
                    // foreign IDs. A mismatch (Phase 3: page deleted on
                    // another device that synced between fetch + reindex)
                    // throws rather than silently skipping the unknown ID
                    // and producing a gap in the index sequence.
                    let known = Set(pageByID.keys)
                    let requested = Set(orderedPageIDs)
                    if known != requested {
                        if let missing = requested.subtracting(known).first {
                            throw NotebookClientError.pageNotFound(missing)
                        }
                        // Caller omitted some pages — fall through and
                        // reindex only the ones they sent (allows partial
                        // reorders if that's the intent).
                    }
                    for (i, id) in orderedPageIDs.enumerated() {
                        pageByID[id]?.index = i
                    }
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },
            transferPage: { pageID, destNotebookID, index in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    guard let dest = try fetchNotebookModel(id: destNotebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(destNotebookID)
                    }
                    let source = page.notebook

                    // Same-notebook "transfer" = reorder. Use reindexPages
                    // semantics instead — keeps the path simpler and
                    // avoids the inverse-relationship dance that would
                    // re-add the page to dest.pages it never left.
                    if let source, source.id == dest.id {
                        var pages = (dest.pages ?? []).sorted { $0.index < $1.index }
                        pages.removeAll { $0.id == page.id }
                        let clamped = min(max(index, 0), pages.count)
                        pages.insert(page, at: clamped)
                        reindex(pages: pages)
                        dest.modifiedAt = calendarContext.now()
                        page.modifiedAt = calendarContext.now()
                        try ctx.save()
                        return
                    }

                    page.notebook = dest

                    // Insert at requested index in destination, then renumber.
                    var destPages = (dest.pages ?? []).sorted { $0.index < $1.index }
                    destPages.removeAll { $0.id == page.id }
                    let clamped = min(max(index, 0), destPages.count)
                    destPages.insert(page, at: clamped)
                    reindex(pages: destPages)

                    if let source {
                        reindex(pages: source.pages ?? [])
                        source.modifiedAt = calendarContext.now()
                    }
                    dest.modifiedAt = calendarContext.now()
                    page.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },
            setPageTemplate: { pageID, templateName in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let now = calendarContext.now()
                    page.templateName = templateName
                    page.modifiedAt = now
                    page.notebook?.modifiedAt = now
                    try ctx.save()
                    return NotePageSnapshot(model: page)
                }
            },

            // MARK: - Page content (high frequency)
            saveDrawing: { pageID, drawingData, thumbnailData in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    page.drawingData = drawingData
                    if let thumbnailData {
                        page.thumbnailData = thumbnailData
                    }
                    let now = calendarContext.now()
                    page.modifiedAt = now
                    page.notebook?.modifiedAt = now
                    try ctx.save()
                }
            },
            updateOCR: { pageID, text in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    page.ocrText = text
                    page.ocrUpdatedAt = calendarContext.now()
                    try ctx.save()
                }
            },
            updateTypedText: { pageID, text in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    page.typedText = text
                    let now = calendarContext.now()
                    page.modifiedAt = now
                    page.notebook?.modifiedAt = now
                    try ctx.save()
                }
            },

            // MARK: - Headers
            addHeader: { pageID, rect, ocrText in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let nextSort = (page.headers ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
                    let header = NoteHeader(
                        page: page,
                        ocrText: ocrText,
                        rect: rect,
                        createdAt: calendarContext.now(),
                        sortOrder: nextSort
                    )
                    ctx.insert(header)
                    page.notebook?.modifiedAt = calendarContext.now()
                    try ctx.save()
                    return NoteHeaderSnapshot(model: header)
                }
            },
            updateHeaderOCR: { headerID, ocrText in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let header = try fetchHeaderModel(id: headerID, ctx: ctx) else {
                        throw NotebookClientError.headerNotFound(headerID)
                    }
                    header.ocrText = ocrText
                    try ctx.save()
                }
            },
            deleteHeader: { headerID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let header = try fetchHeaderModel(id: headerID, ctx: ctx) else {
                        throw NotebookClientError.headerNotFound(headerID)
                    }
                    let parent = header.page?.notebook
                    ctx.delete(header)
                    parent?.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },

            // MARK: - Links
            addLink: { pageID, rect, ocrText, destination in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let link = NoteLink(
                        page: page,
                        ocrText: ocrText,
                        rect: rect,
                        createdAt: calendarContext.now()
                    )
                    apply(destination, to: link)
                    ctx.insert(link)
                    page.notebook?.modifiedAt = calendarContext.now()
                    try ctx.save()
                    return NoteLinkSnapshot(model: link)
                }
            },
            updateLink: { linkID, destination in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let link = try fetchLinkModel(id: linkID, ctx: ctx) else {
                        throw NotebookClientError.linkNotFound(linkID)
                    }
                    apply(destination, to: link)
                    try ctx.save()
                }
            },
            deleteLink: { linkID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let link = try fetchLinkModel(id: linkID, ctx: ctx) else {
                        throw NotebookClientError.linkNotFound(linkID)
                    }
                    let parent = link.page?.notebook
                    ctx.delete(link)
                    parent?.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },

            // MARK: - History
            recordHistory: { pageID, draft in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let entry = NoteHistoryEntry(
                        page: page,
                        kind: draft.kind.historyKind,
                        timestamp: calendarContext.now()
                    )
                    entry.taskTitle = draft.taskTitle
                    entry.taskDestination = draft.taskDestination
                    entry.taskDestinationURL = draft.taskDestinationURL
                    entry.taskEventKitIdentifier = draft.taskEventKitIdentifier
                    // entry.taskStatus retains its "sent" default for newly recorded task entries
                    ctx.insert(entry)
                    page.notebook?.modifiedAt = calendarContext.now()
                    try ctx.save()
                    return NoteHistoryEntrySnapshot(model: entry)
                }
            },
            updateHistoryStatus: { entryID, status in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let entry = try fetchHistoryEntryModel(id: entryID, ctx: ctx) else {
                        throw NotebookClientError.historyEntryNotFound(entryID)
                    }
                    entry.taskStatus = status
                    try ctx.save()
                }
            },

            // MARK: - Regions
            addRegion: { pageID, rect, headerOCRText, linkRecognizedText, linkDestination, eventKitIdentifier in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    // SortOrder grows monotonically from the page's
                    // existing regions so insertion order is stable
                    // across reloads and across re-marking of the
                    // same handwriting region.
                    let nextSort = (page.regions ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
                    let region = NoteRegion(
                        page: page,
                        rect: rect,
                        createdAt: calendarContext.now(),
                        sortOrder: nextSort,
                        headerOCRText: headerOCRText,
                        linkRecognizedText: linkRecognizedText,
                        eventKitIdentifier: eventKitIdentifier
                    )
                    apply(linkDestination, to: region)
                    ctx.insert(region)
                    page.notebook?.modifiedAt = calendarContext.now()
                    try ctx.save()
                    return NoteRegionSnapshot(model: region)
                }
            },
            updateRegionHeader: { regionID, text in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let region = try fetchRegionModel(id: regionID, ctx: ctx) else {
                        throw NotebookClientError.regionNotFound(regionID)
                    }
                    // Empty strings collapse to nil so the snapshot's
                    // `hasAnyAssociation` doesn't keep the header
                    // badge alive for a blank value.
                    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    region.headerOCRText = (trimmed?.isEmpty == false) ? trimmed : nil
                    region.page?.notebook?.modifiedAt = calendarContext.now()
                    try ctx.save()
                    return NoteRegionSnapshot(model: region)
                }
            },
            updateRegionLink: { regionID, destination in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let region = try fetchRegionModel(id: regionID, ctx: ctx) else {
                        throw NotebookClientError.regionNotFound(regionID)
                    }
                    apply(destination, to: region)
                    region.page?.notebook?.modifiedAt = calendarContext.now()
                    try ctx.save()
                    return NoteRegionSnapshot(model: region)
                }
            },
            deleteRegion: { regionID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let region = try fetchRegionModel(id: regionID, ctx: ctx) else {
                        throw NotebookClientError.regionNotFound(regionID)
                    }
                    let parent = region.page?.notebook
                    ctx.delete(region)
                    parent?.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },

            // MARK: - Page blocks
            fetchBlocksForPage: { pageID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    return (page.blocks ?? [])
                        .sorted { $0.sortIndex < $1.sortIndex }
                        .map { PageBlockSnapshot(model: $0, loadDrawingData: false) }
                }
            },
            loadBlockDrawing: { blockID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    return try fetchBlockModel(id: blockID, ctx: ctx)?.drawingData
                }
            },
            insertBlock: { pageID, kind, afterBlockID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let existing = (page.blocks ?? []).sorted { $0.sortIndex < $1.sortIndex }
                    let insertIndex: Int = {
                        guard let afterID = afterBlockID,
                              let after = existing.firstIndex(where: { $0.id == afterID })
                        else { return existing.count }
                        return after + 1
                    }()

                    // Shift existing blocks at/after the insertion point down by 1.
                    for (i, block) in existing.enumerated() where i >= insertIndex {
                        block.sortIndex = i + 1
                    }

                    let now = calendarContext.now()
                    let new = PageBlock(
                        page: page,
                        sortIndex: insertIndex,
                        kind: kind,
                        heightPoints: PageBlock.emptyHeightPoints(for: kind),
                        createdAt: now
                    )
                    ctx.insert(new)
                    page.modifiedAt = now
                    page.notebook?.modifiedAt = now
                    page.recomputeExtractedAggregates()
                    try ctx.save()
                    return PageBlockSnapshot(model: new, loadDrawingData: false)
                }
            },
            updateBlockBody: { blockID, bodyData, plainText in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let block = try fetchBlockModel(id: blockID, ctx: ctx) else {
                        throw NotebookClientError.blockNotFound(blockID)
                    }
                    block.bodyData = bodyData
                    block.plainText = plainText
                    block.contentHash = PageBlock.sha256(plainText)
                    let now = calendarContext.now()
                    block.modifiedAt = now
                    block.page?.modifiedAt = now
                    block.page?.notebook?.modifiedAt = now
                    block.page?.recomputeExtractedAggregates()
                    try ctx.save()
                }
            },
            updateBlockDrawing: { blockID, drawingData, thumbnailData in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let block = try fetchBlockModel(id: blockID, ctx: ctx) else {
                        throw NotebookClientError.blockNotFound(blockID)
                    }
                    block.drawingData = drawingData
                    if let thumbnailData {
                        block.thumbnailData = thumbnailData
                    }
                    // contentHash for ink covers the OCR text; this method
                    // doesn't trigger OCR (the OCR service owns that path).
                    block.contentHash = PageBlock.sha256(block.ocrText ?? "")
                    let now = calendarContext.now()
                    block.modifiedAt = now
                    block.page?.modifiedAt = now
                    block.page?.notebook?.modifiedAt = now
                    block.page?.recomputeExtractedAggregates()
                    try ctx.save()
                }
            },
            updateBlockOCR: { blockID, ocrText in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let block = try fetchBlockModel(id: blockID, ctx: ctx) else {
                        throw NotebookClientError.blockNotFound(blockID)
                    }
                    let now = calendarContext.now()
                    block.ocrText = ocrText
                    block.ocrUpdatedAt = now
                    block.contentHash = PageBlock.sha256(ocrText)
                    // OCR is a derived index, but updating it does
                    // change the page's queryable content (search,
                    // ML inputs). Bump modifiedAt so observers see
                    // the page as "changed" and refresh.
                    block.modifiedAt = now
                    block.page?.modifiedAt = now
                    block.page?.recomputeExtractedAggregates()
                    try ctx.save()
                }
            },
            updateBlockVoice: { blockID, audioData, transcript, confidence, durationSeconds, language in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let block = try fetchBlockModel(id: blockID, ctx: ctx) else {
                        throw NotebookClientError.blockNotFound(blockID)
                    }
                    block.audioData = audioData
                    block.transcript = transcript
                    block.transcriptConfidence = confidence
                    block.audioDurationSeconds = durationSeconds
                    block.transcriptLanguage = language
                    block.contentHash = PageBlock.sha256(transcript)
                    let now = calendarContext.now()
                    block.modifiedAt = now
                    block.page?.modifiedAt = now
                    block.page?.notebook?.modifiedAt = now
                    block.page?.recomputeExtractedAggregates()
                    try ctx.save()
                }
            },
            updateBlockHeight: { blockID, heightPoints in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let block = try fetchBlockModel(id: blockID, ctx: ctx) else {
                        throw NotebookClientError.blockNotFound(blockID)
                    }
                    // No-op for text / voice blocks — they compute their own
                    // height. Only ink blocks honor a user-set drag-bar height.
                    guard block.kind == .ink else { return }
                    let now = calendarContext.now()
                    block.heightPoints = heightPoints
                    block.modifiedAt = now
                    // Drag-bar resize is a user-visible content event —
                    // bump page + notebook modifiedAt so the library
                    // list reflects the touched page.
                    block.page?.modifiedAt = now
                    block.page?.notebook?.modifiedAt = now
                    try ctx.save()
                }
            },
            deleteBlock: { blockID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let block = try fetchBlockModel(id: blockID, ctx: ctx) else {
                        throw NotebookClientError.blockNotFound(blockID)
                    }
                    let page = block.page
                    ctx.delete(block)

                    // Reindex remaining siblings so the sort order stays gapless.
                    let remaining = (page?.blocks ?? [])
                        .filter { $0.id != blockID }
                        .sorted { $0.sortIndex < $1.sortIndex }
                    for (i, sibling) in remaining.enumerated() {
                        sibling.sortIndex = i
                    }

                    let now = calendarContext.now()
                    page?.modifiedAt = now
                    page?.notebook?.modifiedAt = now
                    page?.recomputeExtractedAggregates()
                    try ctx.save()
                }
            },
            reorderBlocks: { pageID, orderedBlockIDs in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let page = try fetchPageModel(id: pageID, ctx: ctx) else {
                        throw NotebookClientError.pageNotFound(pageID)
                    }
                    let blocksByID = Dictionary(
                        uniqueKeysWithValues: (page.blocks ?? []).map { ($0.id, $0) }
                    )
                    // Validate exact set equality before mutating. A
                    // missing ID would leave a block at its old
                    // sortIndex, potentially colliding with the
                    // reordered set; an extra ID would silently no-op.
                    // Both indicate caller bugs that should be loud.
                    let expected = Set(blocksByID.keys)
                    let got = Set(orderedBlockIDs)
                    guard expected == got else {
                        throw NotebookClientError.reorderMismatch(
                            pageID: pageID,
                            expected: expected,
                            got: got
                        )
                    }
                    for (i, id) in orderedBlockIDs.enumerated() {
                        blocksByID[id]?.sortIndex = i
                    }
                    let now = calendarContext.now()
                    page.modifiedAt = now
                    page.notebook?.modifiedAt = now
                    page.recomputeExtractedAggregates()
                    try ctx.save()
                }
            },

            // MARK: - Canonical canvas binding
            bindCanonicalCanvasWidth: { notebookID, width in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(notebookID)
                    }
                    // Idempotent: only set once, then frozen. Gated on
                    // the explicit `canonicalCanvasWidthIsBound` flag
                    // rather than `width == 768` so a user authoring
                    // on a device whose portrait width IS 768 doesn't
                    // re-bind on every first stroke.
                    guard !nb.canonicalCanvasWidthIsBound else { return }
                    nb.canonicalCanvasWidth = width
                    nb.canonicalCanvasWidthIsBound = true
                    // First-stroke is a content event — bump the
                    // notebook's modifiedAt so the library list
                    // reflects the touched notebook.
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },

            // MARK: - Folders
            createFolder: { name, parentID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let parent: Folder?
                    if let parentID {
                        parent = try fetchFolderModel(id: parentID, ctx: ctx)
                        if parent == nil { throw NotebookClientError.folderNotFound(parentID) }
                    } else {
                        parent = nil
                    }
                    let folder = Folder(
                        name: name,
                        createdAt: calendarContext.now(),
                        parent: parent
                    )
                    ctx.insert(folder)
                    try ctx.save()
                    return FolderSnapshot(model: folder)
                }
            },
            deleteFolder: { id in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let folder = try fetchFolderModel(id: id, ctx: ctx) else {
                        throw NotebookClientError.folderNotFound(id)
                    }
                    ctx.delete(folder)   // notebooks nullify; child folders cascade
                    try ctx.save()
                }
            },
            moveNotebookToFolder: { notebookID, folderID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(notebookID)
                    }
                    let folder: Folder?
                    if let folderID {
                        folder = try fetchFolderModel(id: folderID, ctx: ctx)
                        if folder == nil { throw NotebookClientError.folderNotFound(folderID) }
                    } else {
                        folder = nil
                    }
                    nb.folder = folder
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },

            // MARK: - Tags
            createTag: { name, colorHex in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    let tag = Tag(
                        name: name,
                        colorHex: colorHex,
                        createdAt: calendarContext.now()
                    )
                    ctx.insert(tag)
                    try ctx.save()
                    return TagSnapshot(model: tag)
                }
            },
            addTagToNotebook: { tagID, notebookID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let tag = try fetchTagModel(id: tagID, ctx: ctx) else {
                        throw NotebookClientError.tagNotFound(tagID)
                    }
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(notebookID)
                    }
                    var current = nb.tags ?? []
                    if !current.contains(where: { $0.id == tag.id }) {
                        current.append(tag)
                        nb.tags = current
                    }
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            },
            removeTagFromNotebook: { tagID, notebookID in
                try await MainActor.run {
                    let ctx = modelContext.context()
                    guard let nb = try fetchNotebookModel(id: notebookID, ctx: ctx) else {
                        throw NotebookClientError.notebookNotFound(notebookID)
                    }
                    nb.tags = (nb.tags ?? []).filter { $0.id != tagID }
                    nb.modifiedAt = calendarContext.now()
                    try ctx.save()
                }
            }
        )
    }
}

// MARK: - Private fetch helpers

@MainActor
private func fetchNotebookModel(id: UUID, ctx: ModelContext) throws -> Notebook? {
    let descriptor = FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchPageModel(id: UUID, ctx: ModelContext) throws -> NotePage? {
    let descriptor = FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchRegionModel(id: UUID, ctx: ModelContext) throws -> NoteRegion? {
    let descriptor = FetchDescriptor<NoteRegion>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchBlockModel(id: UUID, ctx: ModelContext) throws -> PageBlock? {
    let descriptor = FetchDescriptor<PageBlock>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchFolderModel(id: UUID, ctx: ModelContext) throws -> Folder? {
    let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchHeaderModel(id: UUID, ctx: ModelContext) throws -> NoteHeader? {
    let descriptor = FetchDescriptor<NoteHeader>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchLinkModel(id: UUID, ctx: ModelContext) throws -> NoteLink? {
    let descriptor = FetchDescriptor<NoteLink>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchHistoryEntryModel(id: UUID, ctx: ModelContext) throws -> NoteHistoryEntry? {
    let descriptor = FetchDescriptor<NoteHistoryEntry>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

@MainActor
private func fetchTagModel(id: UUID, ctx: ModelContext) throws -> Tag? {
    let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })
    return try ctx.fetch(descriptor).first
}

// MARK: - Private mutation helpers

/// Reassigns sequential `index` values 0..<pages.count by current
/// `index` order. The result is a contiguous, gap-free sequence.
@MainActor
private func reindex(pages: [NotePage]) {
    let sorted = pages.sorted { $0.index < $1.index }
    for (i, p) in sorted.enumerated() {
        p.index = i
    }
}

/// Writes a `NoteLinkDestination` enum onto a `NoteLink` model's
/// three persisted destination fields, clearing the others. The
/// persistence layer enforces "exactly one non-nil" at this boundary.
@MainActor
private func apply(_ destination: NoteLinkDestination, to link: NoteLink) {
    switch destination {
    case .external(let url):
        link.externalURL = url.absoluteString
        link.targetPageID = nil
        link.targetNotebookID = nil
    case .page(let id):
        link.externalURL = nil
        link.targetPageID = id
        link.targetNotebookID = nil
    case .notebook(let id):
        link.externalURL = nil
        link.targetPageID = nil
        link.targetNotebookID = id
    case .broken:
        // Writing a broken destination is a no-op — the persistence
        // layer never produces it; only reads can yield `.broken` when
        // the underlying record's three destination fields are all nil.
        // Treat as a defensive clear so a caller passing it doesn't
        // silently keep stale data.
        link.externalURL = nil
        link.targetPageID = nil
        link.targetNotebookID = nil
    }
}

/// Applies an optional `NoteRegionLinkDestination` to a `NoteRegion`'s
/// four flat link-target fields, zeroing the others. `nil` clears all
/// four — the region has no link. `.none` and `.broken` are no-ops on
/// the write path; only reads produce them.
///
/// Mirrors the `NoteLink` `apply(_:to:)` shape so the persistence
/// layer keeps a single mental model: the API enforces the
/// exactly-one-non-nil rule at this boundary.
@MainActor
private func apply(_ destination: NoteRegionLinkDestination?, to region: NoteRegion) {
    guard let destination else {
        region.linkExternalURL = nil
        region.linkTargetPageID = nil
        region.linkTargetNotebookID = nil
        region.linkTargetPDFID = nil
        return
    }
    switch destination {
    case .external(let url):
        region.linkExternalURL = url.absoluteString
        region.linkTargetPageID = nil
        region.linkTargetNotebookID = nil
        region.linkTargetPDFID = nil
    case .page(let id):
        region.linkExternalURL = nil
        region.linkTargetPageID = id
        region.linkTargetNotebookID = nil
        region.linkTargetPDFID = nil
    case .notebook(let id):
        region.linkExternalURL = nil
        region.linkTargetPageID = nil
        region.linkTargetNotebookID = id
        region.linkTargetPDFID = nil
    case .pdf(let id):
        region.linkExternalURL = nil
        region.linkTargetPageID = nil
        region.linkTargetNotebookID = nil
        region.linkTargetPDFID = id
    case .none, .broken:
        // No-op on write — same rationale as the NoteLink path.
        region.linkExternalURL = nil
        region.linkTargetPageID = nil
        region.linkTargetNotebookID = nil
        region.linkTargetPDFID = nil
    }
}
