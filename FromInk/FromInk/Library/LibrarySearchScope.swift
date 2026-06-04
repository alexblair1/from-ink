import Foundation

/// Bitmask of kinds the search should consider. Consumers select the
/// scope at use site — the picker variant might want notebooks only,
/// the home browse surface wants all three, a future quick-switcher
/// might add `.page` (OCR full-text). One client, many use sites.
///
struct LibrarySearchScope: OptionSet, Sendable, Equatable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let notebooks = LibrarySearchScope(rawValue: 1 << 0)
    static let folders   = LibrarySearchScope(rawValue: 1 << 1)
    static let pdfs      = LibrarySearchScope(rawValue: 1 << 2)

    /// All currently-implemented scopes. Updated in lockstep when a new
    /// kind lands (e.g., `.page`) — clients that want "everything" stay
    /// future-proof through this constant rather than enumerating cases.
    static let all: LibrarySearchScope = [.notebooks, .folders, .pdfs]
}
