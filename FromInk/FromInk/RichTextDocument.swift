import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "RichTextDocument")

/// The block-tree content shape of a Text `PageBlock`.
///
/// **Why this exists.** The earlier design stored a single
/// `AttributedString` with Foundation's `PresentationIntent` runs
/// inside each Text PageBlock. The 2026-06-09 manual verification
/// confirmed that neither SwiftUI's `TextEditor` (iOS 26) nor
/// `UITextView(usingTextLayoutManager: true)` (TextKit 2) renders
/// block-level `PresentationIntent` visually. The intent persists
/// semantically and the user sees plain prose — every heading, list,
/// blockquote, codeBlock, and divider invisible.
///
/// `RichTextDocument` is the replacement: a rigid Codable schema
/// (ProseMirror-shape) with discrete block kinds that each map to
/// concrete visual treatments via the editor's
/// `BlockDecoratingLayoutManager` (TextKit 1). See
/// `Documentation/text_experience_edd.md` §5.3 for the architectural
/// decision, §5.5 for the PageBlock invariants, §7.3 for the
/// serialization contract.
///
/// **SwiftData safety.** This type is recursive (`indirect`). SwiftData
/// destructures typed Codable properties into composite columns and
/// crashes at runtime when given an `indirect enum` like `Block.Kind`.
/// To avoid that, `PageBlock.bodyData: Data?` stores
/// `JSONEncoder().encode(richTextDocument)` — a Data blob opaque to
/// SwiftData. The document's `version: Int` carries content-shape
/// migrations forward without touching SwiftData's `VersionedSchema`.
///
/// **Forward compatibility.** Decoders are lenient:
/// - Unknown `Mark` cases drop the mark, preserve the inline text.
/// - Unknown `Block.Kind` cases collapse to an empty `.paragraph`,
///   preserving the surrounding tree's structure.
/// A v1 client opening a v2 document keeps every word the user wrote;
/// only the unfamiliar emphasis or block type degrades.
struct RichTextDocument: Codable, Equatable, Sendable {

    /// Schema version. Bumped any time the encoded shape changes in a
    /// way that requires a decoder migration. Content migrations will
    /// live here, not in SwiftData's `VersionedSchema`.
    ///
    /// **Reserved for future use as of v1.** The decoder does not
    /// currently dispatch on `version` — a future-version client
    /// reading a v1 document just decodes with v1 semantics, and vice
    /// versa. When the first content-schema change ships, this is
    /// where the dispatch wires in.
    var version: Int

    /// Ordered top-level blocks. An empty array is a valid document
    /// (the empty block) — the editor renders it with the placeholder.
    var blocks: [Block]

    /// Schema version that this build's encoder stamps on every
    /// document it writes. Reserved — see `version`.
    static let currentVersion: Int = 1

    init(version: Int = RichTextDocument.currentVersion, blocks: [Block] = []) {
        self.version = version
        self.blocks = blocks
    }

    /// Empty document — no blocks. Convenience for new Text PageBlocks
    /// or for `PageBlockSnapshot.decodeBody` failure paths.
    static let empty = RichTextDocument()
}

// MARK: - Block

/// A node in the document tree. Every block has a stable `id` so
/// region anchors (and any future cross-document references) can
/// address a specific block by UUID — index paths would shift on
/// every reorder; UUIDs survive arbitrary edits.
///
/// The recursive shape (`indirect` on `Kind`) is the whole point of
/// the JSON-blob storage strategy — see the type doc on
/// `RichTextDocument`.
struct Block: Codable, Equatable, Sendable, Identifiable {

    var id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// The container/leaf disposition of a block. Containment rules
    /// (which kinds may hold which others) are enforced by the
    /// reducer, not by Swift's type system — every case below is a
    /// valid serialization, but only some combinations form a
    /// well-formed document. See `text_experience_edd.md` §5.3 for
    /// the rigorous containment table.
    indirect enum Kind: Equatable, Sendable {
        case paragraph(inline: [Inline])

        /// Heading level — clamped to 1...3 at the editor boundary;
        /// out-of-range values that arrive via decoded data clamp to
        /// the nearest valid level rather than fail decoding.
        case heading(level: Int, inline: [Inline])

        /// Code block — plain text, no inline marks. The optional
        /// language hint is metadata for future syntax-highlight work.
        case codeBlock(text: String, languageHint: String?)

        case bulletList(items: [ListItem])
        case orderedList(items: [ListItem])

        case blockquote(children: [Block])

        /// Leaf — no payload. Renders as a horizontal rule in the
        /// editor via the `BlockDecoratingLayoutManager`.
        case divider
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case inline
        case level
        case text
        case languageHint
        case items
        case children
    }

    private enum KindTag: String {
        case paragraph
        case heading
        case codeBlock
        case bulletList
        case orderedList
        case blockquote
        case divider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `id` is REQUIRED. Block IDs are the addressing key for
        // NoteRegion text-range anchors (`anchorBlockPath: [UUID]`);
        // silently regenerating a UUID on decode would break every
        // anchor pointing at this block. A producer writing an
        // id-less block is a bug — we fail loudly so it gets caught.
        self.id = try container.decode(UUID.self, forKey: .id)

        // The "type" tag drives which payload fields to read. An
        // unknown tag is the forward-compat path — we degrade to a
        // paragraph but SALVAGE any inline runs the unknown block
        // carried, so the user's words survive across version
        // downgrades. A v2 callout block becomes a v1 paragraph with
        // the same text, instead of a silent empty paragraph.
        let typeRaw = try container.decode(String.self, forKey: .type)
        guard let tag = KindTag(rawValue: typeRaw) else {
            let salvagedInline = try container.decodeIfPresent([Inline].self, forKey: .inline) ?? []
            log.warning(
                "Decoded unknown block kind '\(typeRaw, privacy: .public)' — degraded to paragraph with \(salvagedInline.count) salvaged inline runs"
            )
            self.kind = .paragraph(inline: salvagedInline)
            return
        }

        switch tag {
        case .paragraph:
            let inline = try container.decodeIfPresent([Inline].self, forKey: .inline) ?? []
            self.kind = .paragraph(inline: inline)

        case .heading:
            let rawLevel = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
            // Clamp out-of-range heading levels to the nearest valid
            // level. Decoders never throw on a bad level — losing a
            // heading level is preferable to losing the user's text.
            let level = max(1, min(3, rawLevel))
            let inline = try container.decodeIfPresent([Inline].self, forKey: .inline) ?? []
            self.kind = .heading(level: level, inline: inline)

        case .codeBlock:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            let languageHint = try container.decodeIfPresent(String.self, forKey: .languageHint)
            self.kind = .codeBlock(text: text, languageHint: languageHint)

        case .bulletList:
            let items = try container.decodeIfPresent([ListItem].self, forKey: .items) ?? []
            self.kind = .bulletList(items: items)

        case .orderedList:
            let items = try container.decodeIfPresent([ListItem].self, forKey: .items) ?? []
            self.kind = .orderedList(items: items)

        case .blockquote:
            let children = try container.decodeIfPresent([Block].self, forKey: .children) ?? []
            self.kind = .blockquote(children: children)

        case .divider:
            self.kind = .divider
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch kind {
        case .paragraph(let inline):
            try container.encode(KindTag.paragraph.rawValue, forKey: .type)
            try container.encode(inline, forKey: .inline)

        case .heading(let level, let inline):
            try container.encode(KindTag.heading.rawValue, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(inline, forKey: .inline)

        case .codeBlock(let text, let languageHint):
            try container.encode(KindTag.codeBlock.rawValue, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(languageHint, forKey: .languageHint)

        case .bulletList(let items):
            try container.encode(KindTag.bulletList.rawValue, forKey: .type)
            try container.encode(items, forKey: .items)

        case .orderedList(let items):
            try container.encode(KindTag.orderedList.rawValue, forKey: .type)
            try container.encode(items, forKey: .items)

        case .blockquote(let children):
            try container.encode(KindTag.blockquote.rawValue, forKey: .type)
            try container.encode(children, forKey: .children)

        case .divider:
            try container.encode(KindTag.divider.rawValue, forKey: .type)
        }
    }
}

// MARK: - ListItem

/// A single row in a bulleted or numbered list. The first block in
/// `content` is always a `.paragraph` (the row's text); an optional
/// second block is a nested list. The reducer enforces this — Codable
/// preserves whatever shape is on disk so a future schema expansion
/// (e.g. multi-paragraph list items) doesn't fail to decode v1 data.
struct ListItem: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var content: [Block]

    init(id: UUID = UUID(), content: [Block] = []) {
        self.id = id
        self.content = content
    }
}

// MARK: - Inline

/// A run of text within a leaf block (`paragraph` or `heading`),
/// carrying the marks that apply to its character range.
///
/// Inline runs are the only place inline marks live; `codeBlock` is
/// plain text by construction (no marks) and container kinds hold
/// blocks, not inline runs.
///
/// **Forward-compat decoder.** Custom `init(from:)` iterates the
/// marks array and drops elements that fail to decode (unknown
/// `Mark` tags from a future schema). The user's `text` is preserved
/// verbatim; only the unfamiliar emphasis degrades. `encode(to:)` is
/// synthesised — round-tripping a v1 document is byte-stable under
/// `JSONEncoder(.sortedKeys)`.
struct Inline: Codable, Equatable, Sendable {
    var text: String
    var marks: [Mark]

    init(text: String, marks: [Mark] = []) {
        self.text = text
        self.marks = marks
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case marks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)

        // Iterate marks one slot at a time. `try?` returns nil on an
        // unknown Mark tag without throwing; if it returns nil we
        // explicitly advance past the slot with `EmptyDecodable`,
        // which has no required fields and so accepts any JSON value
        // (including null and arbitrarily-shaped objects). This is
        // the only safe way to skip an unknown element in an
        // UnkeyedDecodingContainer — relying on `decode(_:)` to
        // advance on throw is undefined behaviour.
        var marksContainer = try container.nestedUnkeyedContainer(forKey: .marks)
        var preserved: [Mark] = []
        while !marksContainer.isAtEnd {
            if let mark = try? marksContainer.decode(Mark.self) {
                preserved.append(mark)
            } else {
                _ = try? marksContainer.decode(EmptyDecodable.self)
                log.warning("Decoded unknown inline mark — dropped from run, text preserved")
            }
        }
        self.marks = preserved
    }
}

// MARK: - Mark

/// Inline emphasis applied to a span of text. Designed for expansion
/// — adding a case is forward-compatible because the decoder drops
/// unknown cases rather than throwing (the surrounding inline text
/// survives, only the unfamiliar emphasis degrades).
///
/// See `text_experience_edd.md` §7.4 for the v1 visual contracts.
enum Mark: Codable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case highlight(HighlightKind)
    case link(URL)

    private enum CodingKeys: String, CodingKey {
        case type
        case kind     // for .highlight
        case url      // for .link
    }

    private enum Tag: String {
        case bold
        case italic
        case underline
        case strikethrough
        case code
        case highlight
        case link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .type)
        guard let tag = Tag(rawValue: raw) else {
            // Unknown future mark — the array-level decoder
            // (`Inline.marks`) catches this throw and drops the
            // failing element. Forward-compatibility lives there;
            // here we just declare the failure.
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown mark type \(raw)"
            )
        }
        switch tag {
        case .bold:           self = .bold
        case .italic:         self = .italic
        case .underline:      self = .underline
        case .strikethrough:  self = .strikethrough
        case .code:           self = .code
        case .highlight:
            let kind = try container.decode(HighlightKind.self, forKey: .kind)
            self = .highlight(kind)
        case .link:
            let url = try container.decode(URL.self, forKey: .url)
            self = .link(url)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bold:           try container.encode(Tag.bold.rawValue, forKey: .type)
        case .italic:         try container.encode(Tag.italic.rawValue, forKey: .type)
        case .underline:      try container.encode(Tag.underline.rawValue, forKey: .type)
        case .strikethrough:  try container.encode(Tag.strikethrough.rawValue, forKey: .type)
        case .code:           try container.encode(Tag.code.rawValue, forKey: .type)
        case .highlight(let kind):
            try container.encode(Tag.highlight.rawValue, forKey: .type)
            try container.encode(kind, forKey: .kind)
        case .link(let url):
            try container.encode(Tag.link.rawValue, forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }
}

/// Throwaway type used inside `Inline`'s forward-compat decoder to
/// pop unknown elements without inspecting their shape. Conforms to
/// `Decodable` with no fields, so it accepts any JSON value — null,
/// number, string, array, deeply-nested object — without throwing.
private struct EmptyDecodable: Decodable {}

// MARK: - HighlightKind

/// Visual highlight color. v1 ships four kinds. Adding a case is
/// forward-compatible because raw-value-based String enums decode
/// safely — an unknown future kind falls through to `Mark`'s decoder
/// failure path, which drops the mark while preserving the text.
enum HighlightKind: String, Codable, Hashable, Sendable {
    case yellow
    case red
    case blue
    case green
}

// MARK: - Traversal helpers

extension RichTextDocument {

    /// Walk the document by block-ID path. The path is the chain of
    /// `Block.id` values from the document root to the target leaf.
    ///
    /// **Path skips ListItem IDs** (deliberate). A paragraph inside a
    /// bulletList's first item is addressed `[bulletList.id, paragraph.id]`,
    /// not `[bulletList.id, listItem.id, paragraph.id]`. We chose this
    /// because:
    ///
    ///   - Region anchors (the main caller) only need to address leaf
    ///     blocks (paragraph / heading / codeBlock). They don't need
    ///     to address a ListItem row directly.
    ///   - Path length stays minimal — easier to reason about in tests
    ///     and quicker to walk on render.
    ///
    /// **Trade-off:** if a future feature needs to address a specific
    /// list ROW (e.g. "reorder item X within this list"), it has to
    /// use a different mechanism (ListItem.id directly) rather than
    /// extending this path scheme. Acceptable for v1; revisit when
    /// row-level addressing becomes a requirement.
    ///
    /// Returns nil if the path no longer resolves — typically because
    /// the user deleted a block somewhere along the chain. NoteRegion
    /// anchors call this on every render and flip `isAnchored = false`
    /// on `nil`.
    func block(at path: [UUID]) -> Block? {
        guard !path.isEmpty else { return nil }
        var current: Block? = blocks.first { $0.id == path[0] }
        for id in path.dropFirst() {
            guard let block = current else { return nil }
            current = block.descendants.first { $0.id == id }
        }
        return current
    }
}

extension Block {

    /// Blocks one level deeper inside this block. For leaves, an
    /// empty array. For lists, every block inside every item. For
    /// blockquotes, the direct children. Use for path traversal and
    /// for recursive walks (anchor sweep, plainText derivation).
    var descendants: [Block] {
        switch kind {
        case .paragraph, .heading, .codeBlock, .divider:
            return []
        case .bulletList(let items), .orderedList(let items):
            return items.flatMap(\.content)
        case .blockquote(let children):
            return children
        }
    }

    /// Joined text of a leaf block's inline runs. For `paragraph` and
    /// `heading`, returns the concatenation of `inline.text`. For
    /// `codeBlock`, returns the literal `text`. For container kinds
    /// and `divider`, returns nil — those have no single text payload.
    ///
    /// Used by NoteRegion text-anchor offset math (the offset is in
    /// UTF-16 code units of this string) and by `PageBlock.plainText`
    /// composition.
    var joinedInlineText: String? {
        switch kind {
        case .paragraph(let inline), .heading(_, let inline):
            return inline.reduce(into: "") { $0.append($1.text) }
        case .codeBlock(let text, _):
            return text
        case .bulletList, .orderedList, .blockquote, .divider:
            return nil
        }
    }
}

extension RichTextDocument {

    /// Concatenated plain text across the entire document, suitable
    /// for the `PageBlock.plainText` query mirror.
    ///
    /// Composition strategy (optimized for cheap, deterministic
    /// composition rather than reading nuance):
    ///
    ///   - Every leaf block emits one entry — paragraph + heading
    ///     join their inline runs into a single string; codeBlock
    ///     emits its text; divider emits an empty string.
    ///   - All entries are joined by a single `\n`. We deliberately
    ///     do NOT add extra spacing around headings or between list
    ///     items — search and indexing read the joined text as a
    ///     stream of words, and the cheaper composition gives stable
    ///     content hashes.
    ///   - List items flatten one paragraph per line; blockquote
    ///     contents flatten in place; no quote-marker prefix.
    ///
    /// Order matches the user's reading order — depth-first
    /// in-order traversal.
    var plainText: String {
        var pieces: [String] = []
        appendPlainText(into: &pieces, blocks: blocks)
        return pieces.joined(separator: "\n")
    }

    private func appendPlainText(into pieces: inout [String], blocks: [Block]) {
        for block in blocks {
            switch block.kind {
            case .paragraph(let inline), .heading(_, let inline):
                let joined = inline.reduce(into: "") { $0.append($1.text) }
                pieces.append(joined)
            case .codeBlock(let text, _):
                pieces.append(text)
            case .bulletList(let items), .orderedList(let items):
                for item in items {
                    appendPlainText(into: &pieces, blocks: item.content)
                }
            case .blockquote(let children):
                appendPlainText(into: &pieces, blocks: children)
            case .divider:
                pieces.append("")
            }
        }
    }
}
