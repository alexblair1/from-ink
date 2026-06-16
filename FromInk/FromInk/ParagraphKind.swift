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

extension ParagraphKind {
    /// Derive the leaf-level paragraph kind from a `Block.Kind`,
    /// ignoring any container (list / blockquote) the block sits
    /// inside — callers that need container-aware kinds override
    /// at the wrapping site (see flatten's bullet / ordered / quote
    /// paths). Heading levels are preserved as the associated value;
    /// storage clamps to 1...3 via `attributeValue`.
    init(leafKind: Block.Kind) {
        switch leafKind {
        case .paragraph:             self = .paragraph
        case .heading(let level, _): self = .heading(level: level)
        case .codeBlock:             self = .codeBlock
        case .divider:               self = .divider
        case .bulletList, .orderedList, .blockquote:
            // Containers themselves never flatten as a paragraph
            // (their inner leaves do, with the appropriate kind).
            self = .paragraph
        }
    }

    /// Wire format for the `.paragraphKind` NSAttributedString
    /// attribute. We store an `Int` (boxed as `NSNumber`) rather
    /// than the enum directly because NSAttributedString attribute
    /// equality runs through ObjC `isEqual:`, and stable
    /// `__SwiftValue` boxing for an enum-with-associated-value is
    /// undocumented territory. Heading level clamps to 1...3 — the
    /// side-channel `ParagraphIndex` preserves the original level;
    /// rendering is identical above level 3.
    ///
    /// The integer values intentionally match the old `BlockChrome`
    /// rawValues so any in-memory snapshot (e.g. a paragraph being
    /// re-flattened during inline-toggle surgery) round-trips
    /// without a value translation.
    var attributeValue: Int {
        switch self {
        case .paragraph:           return 0
        case .heading(let level):
            switch level {
            case 1:  return 1
            case 2:  return 2
            default: return 3
            }
        case .bulletListItem:      return 4
        case .orderedListItem:     return 5
        case .blockquoteParagraph: return 6
        case .codeBlock:           return 7
        case .divider:             return 8
        }
    }

    /// Inverse of `attributeValue` — decode an attribute payload
    /// read off NSAttributedString. Returns `nil` for unknown ints
    /// (forward compat with future kinds the storage might carry).
    init?(attributeValue raw: Int) {
        switch raw {
        case 0: self = .paragraph
        case 1: self = .heading(level: 1)
        case 2: self = .heading(level: 2)
        case 3: self = .heading(level: 3)
        case 4: self = .bulletListItem
        case 5: self = .orderedListItem
        case 6: self = .blockquoteParagraph
        case 7: self = .codeBlock
        case 8: self = .divider
        default: return nil
        }
    }
}
