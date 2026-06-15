import Foundation

/// Semantic discriminator for a single paragraph in the editor's
/// flattened NSAttributedString. Drives:
///
///   - The `BlockDecoratingLayoutManager`'s per-paragraph chrome paint
///     (bullet, number, blockquote bar, code tint, divider rule).
///   - Per-paragraph typography in `TextKitEditorView` (heading sizes,
///     code monospace font, blockquote italic).
///   - The reducer-driven structural distinction between "leaf inside a
///     list / blockquote container" and "top-level leaf" — necessary
///     because the document tree wraps containers around their inner
///     paragraphs and the editor surface needs to know which container
///     a paragraph is inside.
///
/// **Why a richer type than `BlockChrome`.** `BlockChrome` was an `Int`
/// raw enum the layout manager probed off NSAttributedString attribute
/// keys. `ParagraphKind` carries the heading level as an associated
/// value instead of three flat cases — matching how the document tree
/// represents headings (`Block.Kind.heading(level:)`) — and lives
/// outside the storage's attribute keys so UIKit's `typingAttributes`
/// mechanism can't strip it or propagate it across Enter. See
/// `Documentation/text_experience_edd.md` §22.4.1 for the
/// imperative-boundary context the ParagraphIndex extends.
///
/// **Stable across mark application.** Inline marks (bold, italic,
/// code, highlight, link) live in NSAttributedString as standard
/// attributes. `ParagraphKind` is paragraph-scoped — it doesn't
/// change when inline marks toggle.
enum ParagraphKind: Equatable, Sendable {
    case paragraph
    case heading(level: Int)
    case bulletListItem
    case orderedListItem
    case blockquoteParagraph
    case codeBlock
    case divider
}
