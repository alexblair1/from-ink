import Foundation

/// One hit in a library search result list. Union of the three library
/// content kinds — notebook, folder, PDF — each carrying its full
/// `Sendable` snapshot so consumers can render rows without a second
/// fetch.
///
/// **Identifiable conformance:** `id` is the underlying snapshot's id,
/// not a discriminated tag, because the three snapshot id-spaces are
/// disjoint UUIDs by construction. A future scope (e.g., `.page` with
/// OCR-snippet results) that *can* collide on id with another scope
/// would need a discriminated id; cross that bridge when it lands.
///
enum LibrarySearchResult: Equatable, Sendable, Identifiable {
    case notebook(NotebookSnapshot)
    case folder(FolderSnapshot)
    case pdf(ImportedPDFSnapshot)

    var id: UUID {
        switch self {
        case .notebook(let s): return s.id
        case .folder(let s):   return s.id
        case .pdf(let s):      return s.id
        }
    }

    /// Display title — used for ranking + row label. Folders use
    /// `name`; notebooks and PDFs use `title`. Pulled into a single
    /// accessor so ranking code doesn't switch over every case.
    var title: String {
        switch self {
        case .notebook(let s): return s.title
        case .folder(let s):   return s.name
        case .pdf(let s):      return s.title
        }
    }

    /// Last-modified timestamp — drives "most recent first" ranking
    /// inside the substring tier. Folders use `createdAt` (they have
    /// no modified timestamp); notebooks + PDFs use their own.
    var rankingDate: Date {
        switch self {
        case .notebook(let s): return s.modifiedAt
        case .folder(let s):   return s.createdAt
        case .pdf(let s):      return s.modifiedAt
        }
    }
}
