import Foundation

/// Discriminator for `NoteRegion`'s anchor. Two kinds:
///
///   • `.inkRect` — anchored to a rectangle on an ink block's canvas.
///     `rectX/Y/W/H` carry canonical-canvas-space coordinates.
///   • `.textRange` — anchored to a span in a text block's
///     `AttributedString`. No offsets stored on the region; the
///     authoritative range lives as a `RegionAnchorAttribute` (UUID =
///     region.id) on the text block's archived body. The editor finds
///     the span at read time by querying runs that carry the matching
///     attribute value.
///
/// See text experience EDD §11.
enum NoteRegionAnchorKind: String, Codable, CaseIterable, Sendable {
    case inkRect
    case textRange
}
