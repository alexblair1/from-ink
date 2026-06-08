import Foundation
import CoreGraphics
import SwiftData

/// A lasso-selected region of ink on a `NotePage` that anchors a set of
/// optional associations: header text (OCR'd from the ink), an external
/// or internal link, and (via separate models) a calendar event and / or
/// reminder. Replaces the pair of `NoteHeader` + `NoteLink` records
/// that previously each anchored a single association per rect.
///
/// **At-most-one per kind.** A region carries at most one of each:
/// one header text, one link destination. The UI prevents the user
/// from adding two headers or two links to the same region. The
/// model layer permits all fields to be set independently (CloudKit-
/// friendly optional storage); enforcement lives at the API boundary.
///
/// **Associations outlive the region.** A region is a *visual anchor*
/// over handwriting; the `CalendarItemLink` for an event lives
/// independently. Erasure-detection logic on the canvas is
/// responsible for flipping `isAnchored = false` when the strokes
/// inside `rect` are gone: the indicator stops rendering, but link
/// records referencing this region survive and remain queryable
/// from the dispatch panel. If the region's `headerOCRText` is
/// also cleared (the OCR was tied to ink that no longer exists)
/// AND no other associations remain, the region is deleted outright.
///
/// **CloudKit notes:**
/// - Every property has a default (`data_model_edd.md` §3.2).
/// - All relationships optional.
/// - `@Relationship(...)` declared on the parent `NotePage.regions`;
///   this child holds the plain `page` back-pointer with no macro to
///   dodge SwiftData's "duplicate inverse" runtime error — same
///   pattern as `NoteHeader` / `NoteLink` and `CalendarItemLink`.
@Model final class NoteRegion {
    var id: UUID = UUID()

    // MARK: Anchor (text experience EDD §11)

    /// The `PageBlock` that owns this region's anchor. nil during the
    /// legacy / pre-block window — the canvas refactor (EDD §22.5)
    /// populates this for every existing region in the same commit
    /// that retires `NotePage.drawingData`. New regions created via
    /// `NotebookClient.addRegion(...)` set this at write time.
    var anchorBlockID: UUID? = nil

    /// Discriminates the anchor shape. `.inkRect` reads `rectX/Y/W/H`;
    /// `.textRange` carries no offsets here — the authoritative span
    /// lives in the text block's archived `AttributedString` as a
    /// `RegionAnchorAttribute` value equal to this region's `id`.
    var anchorKindRaw: String = NoteRegionAnchorKind.inkRect.rawValue

    var anchorKind: NoteRegionAnchorKind {
        get { NoteRegionAnchorKind(rawValue: anchorKindRaw) ?? .inkRect }
        set { anchorKindRaw = newValue.rawValue }
    }

    // Bounding box — CloudKit-friendly scalars, projected through the
    // computed `rect` property below. Same shape as `NoteHeader` /
    // `NoteLink`. Read only when `anchorKind == .inkRect`.
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0

    var createdAt: Date = Date()
    var sortOrder: Int = 0

    /// True iff the region currently anchors to handwriting on the
    /// page. Flipped to false by the erasure sweeper when the strokes
    /// inside `rect` are gone — the canvas stops rendering the
    /// indicator (the badges have nothing to attach to), but any
    /// associations live on (visible in the dispatch panel).
    var isAnchored: Bool = true

    /// At-most-one OCR'd header text. Set at creation when the user
    /// taps "Mark Header" in the lasso menu; editable via the
    /// region's edit sheet; cleared by the erasure sweeper when the
    /// underlying ink is gone (surfacing OCR text anchored to
    /// non-existent strokes would lie).
    ///
    /// **Marker semantics.** Non-nil `headerOCRText` is the canonical
    /// marker for "this region was marked as a header." The dispatch
    /// panel's header list filters on it. The link-creation path must
    /// NOT write to this field — it has its own `linkRecognizedText`
    /// below. Conflating the two would cause a region marked as both
    /// a header AND a link to surface as a duplicate header row.
    var headerOCRText: String? = nil

    /// OCR'd text captured at link-creation time, used only as a
    /// display label on link rows in the dispatch panel. Distinct
    /// from `headerOCRText` so that adding a link to a region does
    /// NOT mark it as a header (and vice versa). nil when the link
    /// has no associated text, or when the region isn't a link at
    /// all.
    var linkRecognizedText: String? = nil

    // Link destination — exactly one of the four target fields is
    // non-nil in any valid persisted state. Stored as flat optional
    // fields rather than a closed enum so CloudKit can sync each
    // independently and partial writes are tolerable. The
    // `NotebookClient` enforces the at-most-one invariant at the API
    // boundary via `NoteRegionLinkDestination`.
    var linkExternalURL: String? = nil
    var linkTargetPageID: UUID? = nil
    var linkTargetNotebookID: UUID? = nil
    /// Reserved — the PDF import + linking flow isn't wired yet. UI
    /// guards prevent setting this until the PDF target story lands;
    /// declared on the model now so adding PDF support later doesn't
    /// require a schema bump.
    var linkTargetPDFID: UUID? = nil

    /// EventKit identifier for a calendar event or reminder anchored
    /// to this region. Set at lasso → Task & Brief completion when
    /// the dispatch modal successfully routes to Calendar or
    /// Reminders. Resolved at render time via
    /// `EKEventStore.event(withIdentifier:)` / `calendarItem(...)`
    /// to fetch the live event for the badge label and tap-to-edit.
    /// nil when the region carries no EK association.
    var eventKitIdentifier: String? = nil

    var page: NotePage? = nil

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        rect: CGRect,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        isAnchored: Bool = true,
        headerOCRText: String? = nil,
        linkRecognizedText: String? = nil,
        linkExternalURL: String? = nil,
        linkTargetPageID: UUID? = nil,
        linkTargetNotebookID: UUID? = nil,
        linkTargetPDFID: UUID? = nil,
        eventKitIdentifier: String? = nil
    ) {
        self.id = id
        self.page = page
        self.rectX = Double(rect.origin.x)
        self.rectY = Double(rect.origin.y)
        self.rectWidth = Double(rect.size.width)
        self.rectHeight = Double(rect.size.height)
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isAnchored = isAnchored
        self.headerOCRText = headerOCRText
        self.linkRecognizedText = linkRecognizedText
        self.linkExternalURL = linkExternalURL
        self.linkTargetPageID = linkTargetPageID
        self.linkTargetNotebookID = linkTargetNotebookID
        self.linkTargetPDFID = linkTargetPDFID
        self.eventKitIdentifier = eventKitIdentifier
    }

    var rect: CGRect {
        CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
    }
}
