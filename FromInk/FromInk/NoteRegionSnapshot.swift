import Foundation
import CoreGraphics

/// Value-type projection of `NoteRegion` — a lasso-selected anchor on
/// a `NotePage` that may carry an OCR'd header text + a link to an
/// external URL or internal page/notebook/PDF. Calendar event /
/// reminder badges are resolved by joining against `CalendarItemLink`
/// at adapter time; they aren't stored on the region itself.
///
/// `rect` is in canvas content coordinates, projected from the model's
/// individual `rectX/Y/Width/Height` scalars.
///
/// `@Model` objects never enter TCA `State` — adapters and reducers
/// consume this snapshot instead.
struct NoteRegionSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageID: UUID
    let rect: CGRect
    let createdAt: Date
    let sortOrder: Int
    /// Mirror of `NoteRegion.isAnchored`. Adapters use this to decide
    /// whether to render the canvas indicator (true) or treat the
    /// region as an orphan visible only in the dispatch panel (false).
    let isAnchored: Bool
    let headerOCRText: String?
    /// OCR'd label captured at link-creation time. Distinct from
    /// `headerOCRText` so a link region doesn't also surface in the
    /// header list. nil when the link carries no label or the region
    /// isn't a link.
    let linkRecognizedText: String?
    let linkDestination: NoteRegionLinkDestination
    /// EventKit identifier when this region anchors a calendar event
    /// or reminder. Resolved at render time via `EventKitService.
    /// fetchEventDraft` for the badge label and tap-to-edit flow.
    let eventKitIdentifier: String?

    /// True when at least one badge would render. The view layer can
    /// use this to early-out the indicator render. `.broken` counts
    /// as an association — the user created a link that's now
    /// corrupt, and the only way they can repair it is by seeing
    /// the broken-link badge and tapping into the edit sheet.
    var hasAnyAssociation: Bool {
        if headerOCRText != nil { return true }
        if eventKitIdentifier != nil { return true }
        switch linkDestination {
        case .none: return false
        case .external, .page, .notebook, .pdf, .broken: return true
        }
    }
}

/// Resolved link destination on a `NoteRegion`. `.none` is the
/// no-link state — a region can carry a header text and no link.
/// `.broken` covers the corruption case where the underlying model
/// carries a non-empty external URL string that fails strict URL
/// parsing. The view layer renders `.broken` as a visible
/// broken-link badge so the user can repair (or remove) it rather
/// than silently routing somewhere.
enum NoteRegionLinkDestination: Equatable, Sendable, Hashable {
    case none
    case external(URL)
    case page(UUID)
    case notebook(UUID)
    case pdf(UUID)
    case broken
}

// MARK: - Conversion from @Model

extension NoteRegionSnapshot {
    init(model: NoteRegion) {
        self.id = model.id
        self.pageID = model.page?.id ?? UUID()
        self.rect = model.rect
        self.createdAt = model.createdAt
        self.sortOrder = model.sortOrder
        self.isAnchored = model.isAnchored
        // Empty header strings collapse to nil so the adapter doesn't
        // render an empty badge for the no-header case (the model
        // permits empty strings for CloudKit flexibility, but the UI
        // treats them as "no header").
        self.headerOCRText = (model.headerOCRText?.isEmpty == false) ? model.headerOCRText : nil
        self.linkRecognizedText = (model.linkRecognizedText?.isEmpty == false) ? model.linkRecognizedText : nil
        self.linkDestination = NoteRegionLinkDestination(model: model)
        self.eventKitIdentifier = (model.eventKitIdentifier?.isEmpty == false) ? model.eventKitIdentifier : nil
    }
}

extension NoteRegionLinkDestination {
    /// Resolves the stored link fields on a `NoteRegion` into the
    /// closed enum. Priority: external URL → page → notebook → PDF →
    /// none. `.broken` is reserved for the case where the model
    /// carries a non-empty externalURL string that fails strict URL
    /// parsing (CloudKit stores it as a string, so a corrupted value
    /// could land).
    ///
    /// External URLs are trimmed before parsing — whitespace-only
    /// strings collapse to `.none` (no link) rather than masquerading
    /// as a `.external` via `URL(string:)`'s lenient behavior.
    init(model: NoteRegion) {
        let trimmedExternal = model.linkExternalURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw = trimmedExternal, !raw.isEmpty {
            if let url = URL(string: raw) {
                self = .external(url)
            } else {
                self = .broken
            }
            return
        }
        if let pageID = model.linkTargetPageID {
            self = .page(pageID)
            return
        }
        if let notebookID = model.linkTargetNotebookID {
            self = .notebook(notebookID)
            return
        }
        if let pdfID = model.linkTargetPDFID {
            self = .pdf(pdfID)
            return
        }
        self = .none
    }
}
