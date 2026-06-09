import Foundation

/// Custom `AttributedString` attribute scope for From Ink's text
/// editor. The scope binds three semantic attributes that the rich-
/// text experience needs:
///
///   • `regionAnchor` (UUID) — pins a `NoteRegion.id` to a span of
///     text. The authoritative range of a text-anchored region lives
///     here, not on the `NoteRegion` row; the editor finds the span
///     at read time by querying runs that carry the matching value.
///     See text experience EDD §11.
///
///   • `highlight` (`HighlightKind`) — visual emphasis (color) and
///     semantic kinds (link / event / PDF) over a span. See EDD §12.
///
///   • `slashInsertion` (`SlashCommandID`) — marks the text inserted
///     by a slash command so the editor can post-process (e.g. render
///     a divider, attach metadata to a link block). See EDD §13.
///
/// Per-attribute boundary semantics:
///
///   • `regionAnchor` has `inheritedByAddedText = false` — load-bearing.
///     Typing past the trailing boundary of a region MUST NOT extend
///     the anchor (a header "Q3 Budget" stays "Q3 Budget" when the
///     user types a space and more text after it).
///   • `highlight` has `inheritedByAddedText = true`. Highlights are
///     visual emphasis; typing past a highlighted span should continue
///     the highlight (matches Apple Notes / Bear / Things). The user
///     can break the highlight explicitly by clearing it from the
///     selection.
///   • `slashInsertion` has `inheritedByAddedText = true`. A slash-
///     inserted span (e.g. a link block) extends if the user types at
///     its trailing edge inside the editor — the inserted unit grows
///     with continued input.
///
/// Inserts strictly INSIDE any span extend it regardless of
/// `inheritedByAddedText` (that's `AttributedString`'s default span-
/// extension behaviour at non-boundary positions).
///
/// Scope conformance enables `AttributedString` Codable round-trip
/// through `JSONEncoder` / `JSONDecoder` via `CodableConfiguration`:
///
///     try JSONEncoder().encode(body, configuration:
///         AttributeScopes.FromInkAttributes.self)
///
///     try JSONDecoder().decode(AttributedString.self, from: data,
///         configuration: AttributeScopes.FromInkAttributes.self)
///
/// Until the slash-command vocabulary and `HighlightKind` ship (later
/// commits in this PR series), the attribute value types are minimal
/// placeholders. The scope itself is wired now so `PageBlockSnapshot
/// .decodeBody` can flip to Path B (Codable) cleanly when the editor
/// lands.
extension AttributeScopes {
    struct FromInkAttributes: AttributeScope {
        let regionAnchor: RegionAnchorAttribute
        let highlight: HighlightAttribute
        let slashInsertion: SlashInsertionAttribute
    }

    /// Strongly-typed accessor for use in keypath syntax:
    ///
    ///     attributed[range].fromInk.regionAnchor = region.id
    ///     attributed.runs[\.fromInk.regionAnchor]
    var fromInk: FromInkAttributes.Type { FromInkAttributes.self }
}

/// Dynamic-lookup conformance so the `fromInk.regionAnchor` keypath
/// resolves through the standard AttributedString attribute API.
/// Auto-synthesis already covers the runtime call sites today, but
/// declaring the subscript explicitly matches Apple's documented
/// pattern for custom attribute scopes and is forward-compatible
/// across SDK revisions.
extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.FromInkAttributes, T>
    ) -> T {
        self[T.self]
    }
}

/// Anchor for a text-range `NoteRegion`. Spans of text that carry a
/// non-nil `RegionAnchorAttribute` value are anchored to the region
/// with that UUID; the canvas indicator and dispatch panel surface
/// them identically to ink-rect regions.
enum RegionAnchorAttribute: CodableAttributedStringKey, Sendable {
    typealias Value = UUID
    static let name = "fromink.regionAnchor"
    static let inheritedByAddedText = false
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = nil
}

/// Visual + semantic highlight over a span. v1 ships color kinds only
/// (`yellow`, `red`, `blue`, `green`); the link / event / PDF custom
/// kinds land with the selection-menu work in PR 2.
///
/// `inheritedByAddedText = true` — typing past a highlighted span
/// extends the highlight, matching the natural emphasis behaviour
/// users expect from Notes / Bear.
enum HighlightAttribute: CodableAttributedStringKey, Sendable {
    typealias Value = HighlightKind
    static let name = "fromink.highlight"
    static let inheritedByAddedText = true
}

/// Discriminator for a span produced by a slash command. Lets the
/// editor post-process inserted spans (e.g. wrap a link-inserted
/// fragment in metadata for the link router). The full slash command
/// vocabulary lands in PR 2 — this minimal placeholder supports the
/// AttributedString Codable round-trip today.
///
/// `inheritedByAddedText = true` — a slash-inserted unit extends as
/// the user keeps typing at its trailing edge.
enum SlashInsertionAttribute: CodableAttributedStringKey, Sendable {
    typealias Value = SlashCommandID
    static let name = "fromink.slashInsertion"
    static let inheritedByAddedText = true
}

/// Visual + semantic highlight kind. The full set lands with the
/// selection menu in a later commit; v1 carries the four default
/// color kinds so the AttributedString Codable round-trip exercises
/// real values rather than placeholders.
enum HighlightKind: String, Codable, Hashable, Sendable {
    case yellow
    case red
    case blue
    case green
}

/// Stable identifier for a slash command. Placeholder until the full
/// `SlashCommand` enum lands in PR 2; until then any future commands
/// just add a string constant.
struct SlashCommandID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}
