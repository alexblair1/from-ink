# From Ink — SwiftData + CloudKit Data Model Engineering Design

> **Status:** Draft
> **Last updated:** 2026-05-08
> **Authors:** Engineering

---

## 1. Goals

1. Every notebook, page, and piece of ink data syncs across the user's devices via CloudKit (private database) with zero server infrastructure.
2. Pages can be transferred between notebooks without data loss.
3. Quick Notes is a first-class section on the home screen backed by a single system notebook.
4. Notes support headers and links that are anchored to specific ink regions on a page.
5. Links can point to external URLs, other pages within the same notebook, or pages in a different notebook entirely.
6. Every page carries invisible OCR text that powers full-text search across all notebooks.
7. Every page carries a historical record of events, tasks, and integration activity that occurred on it.
8. The model respects all CloudKit + SwiftData constraints documented in CLAUDE.md.

---

## 2. CloudKit + SwiftData Constraints

These are non-negotiable. Every design decision in this document is filtered through them.

| Constraint | Implication |
|---|---|
| Every `@Model` property must be optional or have a default value | CloudKit sync silently fails otherwise |
| No `@Attribute(.unique)` | CloudKit does not support unique constraints |
| Non-deterministic defaults (`UUID()`, `Date()`) | CloudKit requires defaults on all non-optional properties, but expressions like `UUID()` produce a new value every evaluation. Property defaults exist to satisfy the framework; the `init` is what callers use. See §2.1 for the canonical pattern. |
| Enums stored as raw `String` | CloudKit cannot encode Swift enums natively |
| No non-optional relationships | CloudKit requires all relationships to be optional |
| `Data` blobs ≤ 1 MB per field for reliable sync | Large ink data must be stored as `CKAsset` (external file) |
| Record zone sharing is per-zone, not per-record | All user data lives in one custom zone |
| Deploy CloudKit schema to Production before App Store submission | Schema changes after production deploy are additive only |

### 2.1 The Canonical `UUID()` Default Pattern

CloudKit + SwiftData requires every non-optional property to have a default value. For identifiers, this creates an unavoidable duplication of `UUID()`:

```swift
@Model final class Notebook {
    var id: UUID = UUID()          // property default — satisfies CloudKit requirement
    // ...
    init(id: UUID = UUID()) {      // init default — gives callers a clean API + injectability
        self.id = id               // assigns from parameter, never calls UUID() directly
    }
}
```

**Four rules this follows:**

1. **Property-level defaults satisfy CloudKit.** They exist so the framework can synthesize objects when hydrating from the store or accepting partial CloudKit records.
2. **Init-level defaults give callers a clean API** and — critically — allow injecting a specific `id` when needed (tests, importing data, server-driven creation).
3. **Inside the init body, assign from the parameter, never call `UUID()` directly.** Writing `self.id = UUID()` instead of `self.id = id` is a bug — it silently discards whatever the caller passed.
4. **`@Attribute(.unique)` is banned with CloudKit**, so the pathological "wrong UUID becomes the upsert key" scenario cannot happen. The `id` is just a regular field that we treat as our logical identifier.

**On hydration safety:** When SwiftData loads from the persistent store, it reads the persisted value through the `_$backingData` mechanism — the property default expression is not re-evaluated. This is observable from the Xcode 15 beta 6→7 fix history (`@Model classes with initial values for stored properties result in an error that self._$backingData is used before being initialized`), which confirms the framework treats property defaults specifically and handles hydration through a separate path. The duplication of `UUID()` between property default and init default is the accepted cost of SwiftData + CloudKit. It is the canonical pattern.

**Deduplication strategy:** Since `@Attribute(.unique)` is unavailable, deduplication after CloudKit sync must be handled in application logic. The standard approach (per Apple's CoreDataCloudKitShare sample) is to listen for `NSPersistentCloudKitContainer.eventChangedNotification`, scan for duplicate UUIDs, keep the first by sort order, and delete or merge the rest.

### External Storage for Large Data

PaperKit `PaperMarkup.dataRepresentation()` produces binary data that can exceed 1 MB for ink-heavy pages. CloudKit has a ~1 MB record size limit.

**Design:** Use `@Attribute(.externalStorage)` on all large `Data` properties (`drawingData`, `thumbnailData`, `sourcePDFData`). This tells SwiftData to store the data outside the SQLite store on disk, and when CloudKit syncs, it automatically promotes them to `CKAsset`. No manual file management or size-based branching needed — the framework handles it.

---

## 3. Model Graph

```
Folder (self-referencing, two-level max enforced in app logic)
  ├─ id: UUID
  ├─ name: String
  ├─ createdAt: Date
  ├─ sortOrder: Int
  ├─ parent: Folder?                ← nil = root folder
  ├─ children: [Folder]?            ← subfolders (cascade delete)
  └─ notebooks: [Notebook]?         ← inverse of Notebook.folder (nullify on delete)

Notebook
  ├─ id: UUID
  ├─ title: String
  ├─ createdAt: Date
  ├─ modifiedAt: Date
  ├─ coverColorHex: String
  ├─ isPinned: Bool                  ← up to 5, enforced in app logic
  ├─ isArchived: Bool                ← hidden from library, still searchable
  ├─ sortOrder: Int                  ← position within folder or root
  ├─ documentKindRaw: String         ← DocumentKind enum as raw value
  │
  │  PDF (populated when documentKind == .pdfDocument)
  ├─ sourcePDFData: Data?            ← @Attribute(.externalStorage) → CKAsset
  │
  │  Relationships
  ├─ folder: Folder?                 ← parent folder
  ├─ pages: [NotePage]?              ← ordered by index (cascade delete)
  ├─ tags: [Tag]?                    ← many-to-many
  └─ highlights: [Highlight]?        ← PDF highlights (cascade delete)

NotePage
  ├─ id: UUID
  ├─ index: Int                      ← order within notebook
  ├─ createdAt: Date
  ├─ modifiedAt: Date
  ├─ templateName: String            ← CanvasTemplate.rawValue
  │
  │  Ink (externalStorage → CKAsset)
  ├─ drawingData: Data?              ← PaperMarkup.dataRepresentation()
  ├─ thumbnailData: Data?            ← rendered preview for home screen cards
  │
  │  PDF (populated when parent is a pdfDocument)
  ├─ pdfPageIndex: Int?              ← index into source PDF
  │
  │  Text
  ├─ ocrText: String?                ← Vision OCR output, powers search
  ├─ ocrUpdatedAt: Date?             ← when OCR was last run
  ├─ typedText: String?              ← for textNote document kind
  │
  │  ML Cache
  ├─ summaryText: String             ← cached page summary
  ├─ summaryHash: String             ← ocrTextHash at time of summary generation
  │
  │  Relationships
  ├─ notebook: Notebook?             ← parent
  ├─ headers: [NoteHeader]?          ← cascade delete
  ├─ links: [NoteLink]?              ← cascade delete
  └─ history: [NoteHistoryEntry]?    ← cascade delete

Tag (many-to-many with Notebook)
  ├─ id: UUID
  ├─ name: String
  ├─ colorHex: String
  ├─ createdAt: Date
  └─ notebooks: [Notebook]?          ← inverse of Notebook.tags

Highlight (PDF annotation, belongs to Notebook not Page)
  ├─ id: UUID
  ├─ createdAt: Date
  ├─ pageIndex: Int                  ← index into source PDF (not a NotePage relationship)
  ├─ extractedText: String           ← OCR text from highlighted region
  ├─ commentary: String              ← user-added note
  ├─ boundsX: Double                 ← normalized 0..1 bounding box
  ├─ boundsY: Double
  ├─ boundsWidth: Double
  ├─ boundsHeight: Double
  └─ notebook: Notebook?             ← parent

NoteHeader
  ├─ id: UUID
  ├─ page: NotePage?                 ← parent
  ├─ ocrText: String                 ← recognized header text
  ├─ rectX: Double                   ← ink region origin x (content coordinates)
  ├─ rectY: Double
  ├─ rectWidth: Double
  ├─ rectHeight: Double
  ├─ createdAt: Date
  └─ sortOrder: Int                  ← vertical order on page

NoteLink
  ├─ id: UUID
  ├─ page: NotePage?                 ← page this link lives on
  ├─ ocrText: String                 ← recognized text of the linked ink region
  ├─ rectX: Double                   ← ink region bounding rect
  ├─ rectY: Double
  ├─ rectWidth: Double
  ├─ rectHeight: Double
  ├─ createdAt: Date
  │
  │  Destination (exactly one of these is non-nil)
  ├─ externalURL: String?            ← https://...
  ├─ targetPageID: UUID?             ← links to a NotePage in same or different notebook
  └─ targetNotebookID: UUID?         ← links to a Notebook (opens at first page)

NoteHistoryEntry
  ├─ id: UUID
  ├─ page: NotePage?                 ← parent
  ├─ timestamp: Date
  ├─ kind: String                    ← "event" | "reminder" | "task_routed" | "task_completed"
  │
  │  Event context (populated when kind == "event")
  ├─ eventTitle: String
  ├─ eventStartDate: Date?
  ├─ eventEndDate: Date?
  ├─ eventCalendarName: String
  │
  │  Reminder context (populated when kind == "reminder")
  ├─ reminderTitle: String
  ├─ reminderDueDate: Date?
  │
  │  Task/integration context (populated when kind starts with "task_")
  ├─ taskTitle: String
  ├─ taskDestination: String          ← Integration.rawValue
  ├─ taskDestinationURL: String
  └─ taskEventKitIdentifier: String?

UserPreferences (local only — separate ModelContainer, NOT synced)
  ├─ id: UUID
  ├─ handedness: String               ← "left" | "right"
  ├─ toolbarSide: String              ← "left" | "right"
  ├─ fingerDrawingEnabled: Bool
  └─ lastOpenedNotebookID: UUID?
```

---

## 4. Model Definitions

### 4.1 Folder

```swift
@Model final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    // Self-referencing: two-level max enforced in app logic, not schema
    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder]? = []

    @Relationship(deleteRule: .nullify, inverse: \Notebook.folder)
    var notebooks: [Notebook]? = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        parent: Folder? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.parent = parent
    }
}
```

**Subfolders:** `parent`/`children` is a self-referencing relationship. Two-level depth max is enforced in app logic (UI disables nesting beyond root → subfolder). Cascade delete on `children` means deleting a folder deletes its subfolders. Nullify on `notebooks` means deleting a folder moves its notebooks to root, not the trash.

### 4.2 Notebook

```swift
@Model final class Notebook {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var coverColorHex: String = "#FAFAF8"
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0

    // Document kind — stored as raw String, exposed via computed property
    var documentKindRaw: String = DocumentKind.notebook.rawValue
    var documentKind: DocumentKind {
        get { DocumentKind(rawValue: documentKindRaw) ?? .notebook }
        set { documentKindRaw = newValue.rawValue }
    }

    // For PDF Document type only
    @Attribute(.externalStorage)
    var sourcePDFData: Data?

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \NotePage.notebook)
    var pages: [NotePage]? = []

    @Relationship(inverse: \Tag.notebooks)
    var tags: [Tag]? = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.notebook)
    var highlights: [Highlight]? = []

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        createdAt: Date = Date(),
        kind: DocumentKind = .notebook,
        coverColorHex: String = "#FAFAF8",
        folder: Folder? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.documentKindRaw = kind.rawValue
        self.coverColorHex = coverColorHex
        self.folder = folder
    }
}

enum DocumentKind: String, Codable {
    case notebook       // Multi-page, scrollable, template per page
    case quickSheet     // Single page, no chrome (Quick Notes)
    case pdfDocument    // PDF with annotation overlay
    case textNote       // Typed text (Mac/iPhone primary)
}
```

**Why `DocumentKind` enum instead of subclasses?** SwiftData inheritance is flaky and CloudKit doesn't support it well. A discriminator enum with type-specific optional fields (`sourcePDFData`, `typedText`) is simpler and works. The computed `documentKind` property gives type-safe access; CloudKit only sees the raw `String`.

**Why `isPinned: Bool` instead of a separate pinned array?** Simpler schema. The "up to 5 pinned" cap is enforced in app logic, not the data layer. Query with `#Predicate { $0.isPinned == true }` sorted by `sortOrder`.

**Why `isArchived: Bool`?** Archived notebooks are hidden from the library grid but remain searchable and syncable. No data loss, no separate trash model.

### 4.3 NotePage

```swift
@Model final class NotePage {
    var id: UUID = UUID()
    var index: Int = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var templateName: String = "blank"

    // Ink — externalStorage promotes to CKAsset automatically
    @Attribute(.externalStorage)
    var drawingData: Data?

    @Attribute(.externalStorage)
    var thumbnailData: Data?

    // PDF page reference (populated when parent is a pdfDocument)
    var pdfPageIndex: Int?

    // OCR
    var ocrText: String?
    var ocrUpdatedAt: Date?

    // Typed text (populated when parent is a textNote)
    var typedText: String?

    // ML cache
    var summaryText: String = ""
    var summaryHash: String = ""

    // Parent
    var notebook: Notebook?

    // Children
    @Relationship(deleteRule: .cascade, inverse: \NoteHeader.page)
    var headers: [NoteHeader]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteLink.page)
    var links: [NoteLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteHistoryEntry.page)
    var history: [NoteHistoryEntry]? = []

    init(
        id: UUID = UUID(),
        index: Int = 0,
        createdAt: Date = Date(),
        templateName: String = "blank",
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.index = index
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.templateName = templateName
        self.notebook = notebook
    }
}
```

**Why is NotePage its own model?** A notebook with 200 pages of dense PencilKit data can easily exceed 100 MB. If drawing data lived on `Notebook`, every library fetch would pull every byte. Splitting lets you `@Query` notebooks for the home grid (cheap) and lazy-fetch a single page when the user opens it.

**`@Attribute(.externalStorage)`:** Tells SwiftData to store `drawingData` and `thumbnailData` outside the SQLite store. When CloudKit syncs, these are automatically promoted to `CKAsset`. Without this, you hit CloudKit's ~1 MB record size limit fast.

**`thumbnailData`:** Pre-rendered page preview stored as `@Attribute(.externalStorage)`. Generated when a page is saved, used by home screen notebook cards. Avoids re-rendering PaperMarkup on the fly for every card in the scroll view.

> **2026-06-09 schema evolution — PageBlock supersedes per-page content fields.** The text experience EDD's block model (`text_experience_edd.md` §5) splits `NotePage`'s content fields into discrete `PageBlock` entities, each with its own payload (`bodyData` for text, `drawingData` + `thumbnailData` for ink, `audioData` + `transcript` for voice). The fields shown above (`drawingData`, `thumbnailData`, `ocrText`, `typedText`) are retiring as the PageBlock model rolls out — see `text_experience_edd.md` §5 for the authoritative current schema and §22.10 for the deletion list.
>
> **PageBlock's text payload now stores a block tree, not an AttributedString.** `PageBlock.bodyData: Data?` holds `JSONEncoder().encode(RichTextDocument)` — a versioned, Codable block tree (paragraph / heading / codeBlock / bulletList / orderedList / blockquote / divider with inline marks). This is the SwiftData-safe form for a recursive Codable type: SwiftData destructures typed Codable properties into composite columns and crashes at runtime when handed an `indirect enum`; storing the encoded `Data` blob keeps the schema flat and content evolutions out of SwiftData migrations (the document carries its own `version: Int` for forward-compatibility).

### 4.4 Tag

```swift
@Model final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#1A1A1A"
    var createdAt: Date = Date()

    var notebooks: [Notebook]? = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#1A1A1A",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}
```

**Many-to-many:** `Tag.notebooks` ↔ `Notebook.tags`. SwiftData handles the join table automatically. Inverse declared on `Notebook` side (`@Relationship(inverse: \Tag.notebooks)`). Deleting a tag removes it from all notebooks. Deleting a notebook removes it from all tags. No cascade — tags and notebooks are peers.

### 4.5 Highlight

```swift
@Model final class Highlight {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var pageIndex: Int = 0
    var extractedText: String = ""
    var commentary: String = ""

    // Bounding box on the source page, normalized 0..1
    var boundsX: Double = 0
    var boundsY: Double = 0
    var boundsWidth: Double = 0
    var boundsHeight: Double = 0

    var notebook: Notebook?

    init(
        id: UUID = UUID(),
        extractedText: String,
        pageIndex: Int,
        createdAt: Date = Date(),
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.extractedText = extractedText
        self.pageIndex = pageIndex
        self.createdAt = createdAt
        self.notebook = notebook
    }
}
```

**Why does Highlight belong to Notebook, not NotePage?** PDF highlights reference a page index into the source PDF, not a `NotePage` model. If highlights were attached to `NotePage`, deleting a notebook page would orphan them. The `pageIndex` here is the PDF page number, resolved at render time.

**Normalized bounds (0..1):** The bounding box is stored relative to page dimensions, not in absolute points. This means highlights survive PDF re-rendering at different scales or on different devices.

### 4.6 NoteHeader

> **STATUS: SUPERSEDED.** `NoteHeader` and `NoteLink` (§4.7) are both replaced by the unified `NoteRegion` (§4.10) as of the 2026-06 region-tool migration. The two models remain in the schema while migration tooling completes; new persistence work uses `NoteRegion`. This section documents the historical shape; consumers should treat it as legacy. **Do not add new fields or call sites to `NoteHeader`.**

```swift
@Model final class NoteHeader {
    var id: UUID = UUID()
    var ocrText: String = ""
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    var page: NotePage?

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        ocrText: String,
        rect: CGRect,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.ocrText = ocrText
        self.rectX = rect.origin.x
        self.rectY = rect.origin.y
        self.rectWidth = rect.size.width
        self.rectHeight = rect.size.height
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.page = page
    }
}
```

**Why individual rect fields instead of `Data`-encoded `CGRect`?** CloudKit indexes scalar fields for efficient queries. If we ever need to query headers by position (e.g. "all headers in the top third of the page"), scalar fields support this. `Data` does not.

### 4.7 NoteLink

> **STATUS: SUPERSEDED.** Replaced by the unified `NoteRegion` (§4.10) alongside `NoteHeader`. See §4.6 status note. Do not add new fields or call sites to `NoteLink`.

```swift
@Model final class NoteLink {
    var id: UUID = UUID()
    var ocrText: String = ""
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0
    var createdAt: Date = Date()

    // Destination — exactly one should be non-nil
    var externalURL: String? = nil
    var targetPageID: UUID? = nil
    var targetNotebookID: UUID? = nil

    var page: NotePage?

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        ocrText: String,
        rect: CGRect,
        createdAt: Date = Date(),
        externalURL: String? = nil,
        targetPageID: UUID? = nil,
        targetNotebookID: UUID? = nil
    ) {
        self.id = id
        self.ocrText = ocrText
        self.rectX = rect.origin.x
        self.rectY = rect.origin.y
        self.rectWidth = rect.size.width
        self.rectHeight = rect.size.height
        self.createdAt = createdAt
        self.externalURL = externalURL
        self.targetPageID = targetPageID
        self.targetNotebookID = targetNotebookID
        self.page = page
    }
}
```

**Link destination resolution:** The view layer reads the three optional fields and resolves:
- `externalURL != nil` → open in Safari/ASWebAuthenticationSession
- `targetPageID != nil` → fetch `NotePage` by id, navigate to it (may be in a different notebook)
- `targetNotebookID != nil` → fetch `Notebook` by id, open at first page
- All nil → broken link (show indicator)

**Why UUID references instead of SwiftData relationships for cross-notebook links?** A `NoteLink` on Page A in Notebook X may point to Page B in Notebook Y. SwiftData relationships + CloudKit cascade deletes would create fragile cross-graph dependencies. UUID references with runtime resolution are safer — a deleted target page simply becomes a broken link, not a cascade failure.

### 4.8 NoteHistoryEntry

```swift
@Model final class NoteHistoryEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var kind: String = ""

    // Event context
    var eventTitle: String = ""
    var eventStartDate: Date? = nil
    var eventEndDate: Date? = nil
    var eventCalendarName: String = ""

    // Reminder context
    var reminderTitle: String = ""
    var reminderDueDate: Date? = nil

    // Task/integration context
    var taskTitle: String = ""
    var taskDestination: String = ""
    var taskDestinationURL: String = ""
    var taskEventKitIdentifier: String? = nil

    var page: NotePage?

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        kind: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.page = page
        self.kind = kind
        self.timestamp = timestamp
    }
}
```

**Why flat fields instead of a JSON blob?** CloudKit can index and query flat fields. History entries may be queried by `kind`, `timestamp`, or `taskDestination` in the future (e.g. "show all Linear tasks created this week across all notebooks"). A JSON blob would require client-side deserialization for every query.

### 4.9 UserPreferences (local only)

```swift
@Model final class UserPreferences {
    var id: UUID = UUID()
    var handedness: String = "right"
    var toolbarSide: String = "left"
    var fingerDrawingEnabled: Bool = false
    var lastOpenedNotebookID: UUID?

    init(id: UUID = UUID()) {
        self.id = id
    }
}
```

**This model does NOT sync.** Toolbar side, handedness, and last-opened notebook are per-device preferences. They live in a separate `ModelContainer` with `cloudKitDatabase: .none`, even after the synced container moves to `.private(...)` in Phase 3.

### 4.10 NoteRegion

`NoteRegion` is a lasso-selected anchor on a `NotePage` that carries any combination of associations: an OCR'd header text, a link destination (external URL, page, notebook, or PDF reference), and an EventKit identifier for an anchored calendar event or reminder. Replaces the pair of `NoteHeader` (§4.6) and `NoteLink` (§4.7), which together couldn't represent a region that's both a header AND an event, or a link AND an event, without producing duplicate records.

```swift
@Model final class NoteRegion {
    var id: UUID = UUID()

    // Bounding box — CloudKit-friendly scalars, projected through
    // the computed `rect` property below. Same shape as the legacy
    // NoteHeader / NoteLink so the migration is purely additive.
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0

    var createdAt: Date = Date()
    var sortOrder: Int = 0

    /// True iff the region currently anchors to handwriting on the
    /// page. Flipped to false by the erasure sweeper when the strokes
    /// inside `rect` are gone.
    var isAnchored: Bool = true

    /// OCR'd header text — the canonical marker for "this region was
    /// marked as a header." The dispatch panel's header list filters
    /// on `headerOCRText != nil`. The link-creation path must NOT
    /// write to this field (it has its own `linkRecognizedText`).
    var headerOCRText: String? = nil

    /// OCR'd label captured at link-creation time. Distinct from
    /// `headerOCRText` so that adding a link to a region does NOT
    /// also mark it as a header. nil when the link has no associated
    /// label or the region isn't a link.
    var linkRecognizedText: String? = nil

    // Link destination — exactly one of the four target fields is
    // non-nil in any valid persisted state. Flat optional fields
    // rather than a closed enum so CloudKit syncs each independently
    // and partial writes are tolerable.
    var linkExternalURL: String? = nil
    var linkTargetPageID: UUID? = nil
    var linkTargetNotebookID: UUID? = nil
    var linkTargetPDFID: UUID? = nil

    /// EventKit identifier for a calendar event or reminder anchored
    /// to this region. Set at lasso → Task & Brief completion when
    /// the dispatch modal successfully routes to Calendar or
    /// Reminders. Resolved at render time via `EKEventStore.event(
    /// withIdentifier:)` / `calendarItem(withIdentifier:)`. nil when
    /// the region carries no EK association.
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
        // ... assignments ...
    }
}
```

**Marker semantics — load-bearing.** The dispatch panel filters its header list by `headerOCRText != nil` and its link list by `linkDestination != .none`. The two fields are deliberately distinct so that a region can be a link (with `linkRecognizedText` populated as a display label) without also surfacing as a header — and vice versa. Conflating the two via a single `ocrText` field is the bug that bit the codebase in June 2026 (links over previously-marked-header handwriting produced phantom duplicate header rows); the split into two fields is the canonical fix. **Future contributors: do NOT add a generic `ocrText: String` field. The semantic distinction is the design.**

**At-most-one-per-kind, enforced at the API boundary.** The model permits all fields to be set independently (CloudKit-friendly optional storage); the `NotebookClient` enforces "one header text, one link destination" at the `addRegion` / `updateRegionHeader` / `updateRegionLink` boundary. A region with header + link + event is valid (and intended); a region with two link destinations is not (`updateRegionLink` clears the other three target fields when setting one).

**Associations outlive the region.** When the erasure sweeper detects the strokes inside `rect` are gone, it flips `isAnchored = false` rather than deleting the region. The canvas stops rendering the indicator, but link / event associations live on, visible in the dispatch panel. If `headerOCRText` is also cleared AND no other associations remain, the region is deleted outright.

**Why the `eventKitIdentifier` is a flat String, not a separate `CalendarItemLink` join table.** The integration matrix EDD's V1 row treats native EventKit as a primary integration without server-side metadata; a separate join table would add joins to every region render without buying anything that `EKEventStore.event(withIdentifier:)` doesn't already provide locally. If V2 ever adds remote-source events (e.g. shared Linear or Notion calendars), a `CalendarItemLink` join may be added then; the region's `eventKitIdentifier` field would remain for native EK items and the new field for the V2 path.

**Snapshot normalization.** `NoteRegionSnapshot` collapses empty strings to nil for `headerOCRText`, `linkRecognizedText`, and `eventKitIdentifier`. The model permits empty strings for CloudKit-write tolerance, but the UI treats them as the no-association state. This is the canonical contract for any future string field added to `NoteRegion`: store-tolerant, read-strict.

**Why scalar rect fields instead of `Data`-encoded `CGRect`?** Same reasoning as §4.6 — CloudKit indexes scalar fields for efficient queries. If a future feature ever queries regions by position (e.g. "all regions in the top third of the page"), scalar fields support this.

---

## 5. Document Kinds

The `DocumentKind` enum on `Notebook` determines the editing experience and UI chrome:

| Kind | Pages | Canvas | Chrome | Primary input |
|---|---|---|---|---|
| `notebook` | Multi-page, scrollable | PaperKit | Full toolbar, template picker | Apple Pencil |
| `quickSheet` | Single page, no pagination | PaperKit | Minimal — no page navigator | Apple Pencil |
| `pdfDocument` | One `NotePage` per PDF page | Annotation overlay | PDF navigation, highlight tools | Apple Pencil + tap |
| `textNote` | Single page | None | Keyboard toolbar | Keyboard (Mac/iPhone primary) |

### Quick Notes

Quick Notes uses `documentKind == .quickSheet`. Each quick note is its own single-page `Notebook` with `documentKindRaw == "quickSheet"`. There is no single "Quick Notes notebook" — each quick note is independent and appears in the Quick Notes section of the home screen.

```swift
// Creating a new quick note
let quickNote = Notebook(title: "Quick Note", kind: .quickSheet)
let page = NotePage(index: 0, notebook: quickNote)
context.insert(quickNote)
```

**Querying quick notes for the home screen:**
```swift
let descriptor = FetchDescriptor<Notebook>(
    predicate: #Predicate { $0.documentKindRaw == "quickSheet" },
    sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
)
```

**Behavior:**
- Quick notes appear in their own home screen section, not in the notebooks strip.
- A quick note page can be transferred to a regular notebook (its parent notebook's `documentKindRaw` changes to `"notebook"`, or the page is moved to an existing notebook).
- Quick notes cannot be moved to folders.
- Quick notes are not pinnable.

---

## 6. Page Transfer

Moving a page from Notebook A to Notebook B:

```swift
func transferPage(_ page: NotePage, to destination: Notebook, at index: Int) {
    // 1. Remove from source
    page.notebook = destination

    // 2. Reindex destination
    let destPages = (destination.pages ?? [])
        .sorted { $0.pageIndex < $1.pageIndex }
    for (i, p) in destPages.enumerated() {
        p.pageIndex = i
    }

    // 3. Reindex source (handled by caller after removal)
}
```

**What transfers with the page:**
- `inkData`, `ocrText`, `ocrTextHash`, `summaryText`, `summaryHash` — all stay on the page
- `headers` and `links` — cascade with the page (relationship)
- `history` — cascades with the page (relationship)
- Internal links pointing TO this page (from other pages) remain valid because they reference `page.id` (UUID), which doesn't change

**What doesn't transfer:**
- The page's `pageIndex` is reassigned to fit the destination notebook's ordering

---

## 7. Search

The search bar on the home screen queries across two dimensions:

### 7.1 Notebook title search (existing)
```swift
notebooks.filter { $0.title.localizedCaseInsensitiveContains(query) }
```

### 7.2 Full-text page search (new)
```swift
let pageDescriptor = FetchDescriptor<NotePage>(
    predicate: #Predicate { $0.ocrText.localizedStandardContains(query) }
)
let matchingPages = try context.fetch(pageDescriptor)
```

**Search results model:**
```swift
struct SearchResult: Identifiable {
    let id: UUID
    let kind: SearchResultKind
    let title: String        // notebook title or page excerpt
    let subtitle: String     // "Page 3 of Quarterly Review" or "5 notebooks"
    let notebookID: UUID
    let pageID: UUID?        // nil for notebook-level matches

    enum SearchResultKind {
        case notebook
        case page
    }
}
```

**Performance:** `ocrText` is stored as a plain `String` field. CloudKit indexes string fields by default. For local queries, SwiftData uses SQLite `LIKE` under the hood, which is sufficient for the expected data volume (hundreds of pages, not millions). If performance becomes an issue, we can add a local Core Spotlight index.

---

## 8. OCR Pipeline Integration

```
Stroke completed
    ↓ (800ms debounce)
VNRecognizeTextRequest (.accurate, customWords)
    ↓
Normalize output (trim, collapse whitespace, normalize punctuation)
    ↓
Store in NotePage.ocrText
    ↓
Compute SHA256 → NotePage.ocrTextHash
    ↓
Compare against NotePage.summaryHash
    ↓ (>20% edit distance)
Re-run summarization → NotePage.summaryText, update summaryHash
    ↓ (>10% edit distance)
Re-run task extraction → NoteHistoryEntry records
```

The `ocrTextHash` field enables cheap staleness detection without re-running OCR. The `summaryHash` field records which version of OCR text the current summary was generated from.

---

## 9. Development Phases

### Core principle: Model as if CloudKit is on. Keep the runtime off until ready.

CloudKit's constraints — defaults on every non-optional property, optional relationships with inverses, no `@Attribute(.unique)`, enums as raw strings — are **model design constraints**, not integration concerns. They shape how `@Model` classes are written from the first line. Building a local-only SwiftData layer without these rules, then trying to "add CloudKit later," means rewriting every model.

The correct approach: follow every CloudKit rule from day one, but configure `cloudKitDatabase: .none` so there is no runtime cost and no schema committed to any CloudKit container. This gives free local iteration (delete the app to reset) while guaranteeing that enabling CloudKit is a configuration change, not a refactor.

### Phase 1: CloudKit-shaped, locally persisted (current → near-term)

All models follow CloudKit rules. No iCloud entitlement. No CloudKit container.

```swift
// FromInkApp.swift — Phase 1: dual containers

// Synced models (cloudKitDatabase: .none for now, .private(...) in Phase 3)
let syncedConfig = ModelConfiguration(
    schema: Schema([
        Notebook.self,
        NotePage.self,
        NoteHeader.self,
        NoteLink.self,
        NoteHistoryEntry.self,
        Folder.self,
        Tag.self,
        Highlight.self,
        RoutedItem.self,
    ]),
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none
)
let syncedContainer = try ModelContainer(
    for: syncedConfig.schema,
    configurations: syncedConfig
)

// Local-only models (never synced, even when CloudKit is enabled)
let localConfig = ModelConfiguration(
    schema: Schema([UserPreferences.self]),
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none
)
let localContainer = try ModelContainer(
    for: localConfig.schema,
    configurations: localConfig
)
```

During this phase:
- Change models freely — delete the app to reset the local store
- No `VersionedSchema` needed yet — lightweight migrations handle additive changes locally
- Remove `Item.self` from the container now (placeholder from project template, CloudKit has never seen it)
- Test with realistic data volumes (50+ notebooks, 500+ pages) to catch performance issues early
- `UserPreferences` always stays in the local container — toolbar side, handedness, and last-opened notebook are per-device

**CloudKit readiness checklist (enforce in code review from day one):**
- [ ] Every non-optional property has a default value
- [ ] Every relationship is optional with an inverse
- [ ] No `@Attribute(.unique)` anywhere
- [ ] Enums stored as raw `String` via a private property, exposed via computed property
- [ ] No required-by-business-logic fields without a sensible default
- [ ] `init` parameters include `id: UUID = UUID()` for injectability; body assigns from parameter (`self.id = id`), never calls `UUID()` directly

### Phase 2: Lock schema + add versioning (pre-CloudKit)

Once the model graph is stable and the application is fully functional, lock it down with `VersionedSchema`. This is the schema CloudKit will see for the first time.

**Do not enter Phase 2 until all of the following are true:**
- All `@Model` classes in this document are implemented and tested
- Canvas persistence (ink data → NotePage) is working end-to-end
- Page transfer between notebooks is working
- Quick Notes is working
- Search across OCR text is working
- Headers and links are persisted and rendered
- History entries are being created from EventKit and dispatch
- The model graph has been stable (no schema changes) for at least 2 weeks

```swift
enum FromInkSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Notebook.self,
            NotePage.self,
            NoteHeader.self,
            NoteLink.self,
            NoteHistoryEntry.self,
            Folder.self,
            Tag.self,
            Highlight.self,
            RoutedItem.self,
        ]
    }
}

enum FromInkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FromInkSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No stages yet — V1 is the first version CloudKit will ever see.
        // Future versions add .lightweight stages here.
    }
}
```

```swift
// FromInkApp.swift — Phase 2 (versioned, still cloudKitDatabase: .none)
// Synced container
let syncedConfig = ModelConfiguration(
    schema: Schema(FromInkSchemaV1.models),
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none
)
let syncedContainer = try ModelContainer(
    for: Schema(FromInkSchemaV1.models),
    migrationPlan: FromInkMigrationPlan.self,
    configurations: syncedConfig
)

// Local container (UserPreferences — never versioned with CloudKit schema)
let localConfig = ModelConfiguration(
    schema: Schema([UserPreferences.self]),
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none
)
let localContainer = try ModelContainer(
    for: localConfig.schema,
    configurations: localConfig
)
```

**Rules for future schema versions (from this point forward):**
- Every new version gets a `FromInkSchemaVN` with a full copy of all model types at that version
- Only `.lightweight` migration stages — custom stages do not work reliably with CloudKit sync
- **Never remove a property** from a model — only deprecate it (stop writing to it, ignore on read)
- **Never rename a property** — add a new one and deprecate the old
- `UserPreferences` is excluded from `VersionedSchema` — it lives in a separate local-only container and can be changed freely

### Phase 3: Enable CloudKit in Development (pre-launch)

The single-line change — `syncedConfig` switches from `.none` to `.private(...)`. The local container stays `.none` forever.

```swift
// FromInkApp.swift — Phase 3 (CloudKit enabled on synced container only)
let syncedConfig = ModelConfiguration(
    schema: Schema(FromInkSchemaV1.models),
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .private("iCloud.com.fromink.app")
)
let syncedContainer = try ModelContainer(
    for: Schema(FromInkSchemaV1.models),
    migrationPlan: FromInkMigrationPlan.self,
    configurations: syncedConfig
)

// Local container — unchanged, always .none
let localConfig = ModelConfiguration(
    schema: Schema([UserPreferences.self]),
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none
)
let localContainer = try ModelContainer(
    for: localConfig.schema,
    configurations: localConfig
)
```

Prerequisites:
1. Add the iCloud entitlement and CloudKit container (`iCloud.com.fromink.app`) in Xcode capabilities
2. Run on a **physical device** signed into iCloud — this auto-creates the Development schema

Testing checklist:
- [ ] Verify all record types and fields at `icloud.developer.apple.com`
- [ ] Sync between two physical devices (iPhone + iPad)
- [ ] Conflict resolution: edit the same notebook on two devices offline, bring both online
- [ ] Large ink data sync (pages with heavy drawing)
- [ ] Offline → online: create notebooks and pages offline, verify they sync when connectivity returns
- [ ] Deduplication: verify post-sync dedup logic handles records arriving out of order
- [ ] Relationship materialization: verify pages arrive after their parent notebook without errors

**Important:** `cloudKitDatabase: .none` vs `.private(...)` is the only difference between local-only and CloudKit-synced. Because the models already follow every CloudKit rule, this transition is a configuration change, not a refactor.

### Phase 3 pre-flip checklist — sync-correctness review findings (2026-06-10)

The "configuration change, not a refactor" claim above holds for the *schema*. A 2026-06-10 review found five places where the **write patterns** assume a single writer and will misbehave once a second device exists. All five are cheap to fix before the Development schema is created and expensive after (CloudKit schemas never delete fields). Each is a release gate for the Phase 3 flip:

- [ ] **1. `PageBlock.bodyData` storage decision must match real block sizes.** `bodyData` is deliberately inline (not `.externalStorage`) on a "200B–2KB per paragraph" assumption — but the shipped editor currently stores the *entire page's* `RichTextDocument` JSON in ONE text block, which can reach hundreds of KB. A record exceeding CloudKit's 1 MB limit fails to sync **silently and per-record** — the user's largest note is exactly the one that stops syncing. Resolve jointly with the editor roadmap: either flip `bodyData` to `@Attribute(.externalStorage)` (one attribute, zero migration cost pre-flip) or enforce the many-small-text-blocks model from text_experience_edd §5 before sync ships. Decide **before** the Development schema exists.
- [ ] **2. Denormalized page aggregates go stale under per-record LWW.** `NotePage.extractedText` / `extractedTextHash` and `PageBlock.contentHash` are recomputed locally at write time (`recomputeExtractedAggregates()`). When device A edits block 3 and device B edits block 5 concurrently, the *blocks* merge correctly per-record, but the page-level aggregate is one field on one record — LWW keeps one device's aggregate, which reflects **neither** merged state. Search, VoiceOver page reading, and ML cache invalidation all read off it. Fix: treat aggregates as local derived caches — recompute on remote-change import (or lazily when the manifest disagrees with the blocks), and prefer excluding them from sync entirely.
- [ ] **3. Gapless reindexing is a mass-write conflict machine.** `insertBlock` shifts every subsequent block's `sortIndex`; `deleteBlock` and `reorderBlocks` rewrite every sibling; `NotePage.index` has the same shape. One insert at the top of a 50-block page dirties 50 records; two devices doing structural edits concurrently interleave per-record LWW into colliding indexes and a garbled page. Fix: **fractional ordering** (insert at the midpoint between neighbors; tolerate gaps; reindex only on precision exhaustion) so an insert touches exactly one record. Also relax `reorderBlocks`' strict set-equality throw — it will fire on legitimate Phase 3 races (block deleted remotely between fetch and reorder), the same race already anticipated for pages in `reindexPages`.
- [ ] **4. CKAssets download eagerly, not lazily.** text_experience_edd §8.4 previously claimed assets lazy-fetch on field access. Reality: `NSPersistentCloudKitContainer` (which SwiftData wraps) downloads assets **at sync-import time**. `.externalStorage` gives lazy faulting *from local disk*, not deferred *network* fetch. A fresh device downloads every voice memo and ink drawing in the library up front. Acceptable for a private-DB notes app, but: keep `audioData` clearable post-transcription (the snapshot shape already allows it), and don't design first-run UX assuming on-demand asset fetch.
- [ ] **5. App-level dedup sweep exists for PDFs only.** Uniqueness is application-enforced (no `@Attribute(.unique)` under CloudKit); the mirroring layer can produce duplicate records for simultaneous offline creates. `ImportedPDF` has hash-dedup; Notebook / Folder / Tag have none. Implement the post-import dedup pass (listen for the container event notification, scan duplicate `id` UUIDs, keep-first-merge-rest) before the flip — it's already on the Phase 3 testing checklist but has no implementation.

Two smaller items, same timing:

- **Observation fan-out.** `ModelStoreObserver` matches `NSManagedObjectContextDidSave` by name only — every save in the process (including the local-only preferences container) ticks every observing feature. Filter by container/entity before sync multiplies save frequency. Note also that SwiftData does not expose the store option that enables `.NSPersistentStoreRemoteChange` posts; the Phase 3 remote-change source will likely need `ModelContext.didSave` (iOS 18+) instead — verify before counting on it.
- **`Notebook.canonicalCanvasWidth` bind race.** Two different-width iPads binding on first stroke concurrently → LWW flips the canonical width under one device's already-recorded strokes. Either accept (ink authoring is iPad-only, narrow window) or pin the canonical width to the fixed 768pt default and drop the bind-on-first-stroke behavior.

Legacy-field cleanup (`NotePage.drawingData` / `ocrText` / `typedText` / `summaryText` / `summaryHash`, the `headers` + `links` consumer paths) must also land **before** the Development schema is first created, per §22.10 of the text experience EDD.

### Phase 4: Deploy to production (App Store submission)

1. **Deploy CloudKit schema from Development → Production** in the CloudKit Dashboard. This is irreversible.
2. After this point, all schema changes are additive only — you cannot remove fields, change types, or rename anything.
3. Submit to the App Store.

### CloudKit sync considerations (for Phase 3+)

- SwiftData + CloudKit does not support `@Attribute(.unique)`. All uniqueness is enforced in application logic via post-sync deduplication.
- Relationships are stored as CKReferences. Cascade deletes in SwiftData map to `CKRecord.Reference` with `.deleteSelf` action.
- Conflict resolution uses CloudKit's default last-writer-wins per-field merge. For ink data, this means the last device to save a stroke wins. Acceptable for single-user sync (the user is only drawing on one device at a time).
- Deduplication: listen for `NSPersistentCloudKitContainer.eventChangedNotification`, scan for duplicate UUIDs, keep the first by sort order, delete or merge the rest.
- There is no Apple-blessed migration path from "local-only SwiftData" to "CloudKit-synced SwiftData." By following CloudKit rules from Phase 1, we avoid this entirely — the store is CloudKit-compatible from its first write.

---

## 10. Design Rationale

Decisions that were considered carefully and are now locked.

| Decision | Rationale |
|---|---|
| `NotePage` is its own model, not a property on `Notebook` | A 200-page notebook with dense PencilKit data could be 100 MB+. Splitting lets you `@Query` notebooks cheaply and lazy-fetch pages on open. |
| `@Attribute(.externalStorage)` on blob fields | Auto-promotes to CKAsset on sync. Without this, you hit CloudKit's 1 MB record limit. |
| `DocumentKind` enum on `Notebook`, not subclasses | SwiftData inheritance is flaky and CloudKit doesn't support it. A discriminator enum with type-specific optional fields is simpler. |
| `Highlight` belongs to `Notebook`, not `NotePage` | PDF highlights reference a page index into the source PDF, not a `NotePage`. Attaching to `NotePage` would orphan highlights on page deletion. |
| `Folder` → `Notebook` delete rule is `.nullify` | Deleting a folder moves its notebooks to root, not the trash. Less destructive than `.cascade`. |
| `Folder` → `children` delete rule is `.cascade` | Deleting a parent folder deletes its subfolders. Two-level max means this is always intentional. |
| `UserPreferences` in a separate local-only container | Toolbar side, handedness, last-opened notebook are per-device. Syncing them would cause devices to fight over state. |
| Smart collections (Today, This Week, etc.) are query-time, not stored | No model needed. Build with `#Predicate` at the view layer. |

---

## 11. Retention

### 11.1 The regenerable / authored split

Every persisted model in From Ink belongs to one of two retention classes. The class dictates how aggressively the system can reclaim space.

| Class | Examples | Reclamation policy |
|---|---|---|
| **Authored** — user produced this content; we cannot recreate it | `Notebook`, `NotePage` (drawing data, OCR text the user wrote), `Folder`, `Tag`, `NoteHeader`, `NoteLink`, `Highlight`, `NoteHistoryEntry`, attached media | **Never silently delete.** Eviction requires explicit user action ("Empty Trash"). CloudKit sync is the only thing that moves these around. |
| **Regenerable** — derived from external sources we can re-query | `DailyBriefRecord` (text comes from EventKit + Foundation Models; both inputs reproducible), future FM summaries / extracted tasks / page indexes | **Safe to silently evict** when storage pressure or staleness warrants. Cost of eviction is one regeneration (~few seconds of FM time) on next access. |

This is the load-bearing distinction. Storage strategy follows from class membership: authored data is conservative, regenerable data is opportunistic.

### 11.2 `DailyBriefRecord` retention policy (V1)

`DailyBriefRecord` is the regenerable model that's in production. Its policy proves the pattern for future regenerable models (FM summaries, extracted tasks).

**Schema affordances**

```swift
@Model final class DailyBriefRecord {
    var lastAccessedAt: Date = Date()   // touch-on-read with debounce

    static let evictionThreshold: Int = 5_000   // start evicting above this
    static let evictionTarget:    Int = 4_500   // drop to this when we do
    static let touchInterval: TimeInterval = 60 * 60   // debounce read writes
}
```

**Touch-on-read (debounced).** Every time `DailyBriefClient` returns a record from cache (`_fetchOrGenerate` cache-hit path, `_fetch`, `regenerate`), it bumps `lastAccessedAt` — but only if the previous touch is older than `touchInterval` (1 hour). Without the debounce, every appeared / foregrounded / wheel scroll would dirty the store and trigger CloudKit churn. Hour-granularity is sufficient signal for LRU ordering.

**LRU eviction.** Triggered exclusively after a successful `generateNew` insert. Logic:

1. `context.fetchCount(FetchDescriptor<DailyBriefRecord>())`.
2. If count ≤ `evictionThreshold` → no-op.
3. Otherwise fetch the oldest `(count - target)` records, ordered by `lastAccessedAt` ascending. Delete them, save.

The threshold-to-target gap is a **hysteresis band** — without it, every subsequent insert at the threshold would evict exactly one record. The gap means eviction runs occasionally and removes ~500 records at a time, which is cheaper than 500 individual evictions.

**Trigger surface.** Eviction runs only after `generateNew` saves a new record. This is the only growth path for the record set, so one trigger point suffices. Reads, regen-in-place, and `refresh` do not trigger eviction (they don't grow the set).

### 11.3 Sizing the threshold

`DailyBriefRecord` is ~2 KB on disk including SwiftData / CloudKit row overhead. The threshold-to-storage map:

| Threshold | Storage at full | Years of daily use |
|---|---|---|
| 500 | ~1 MB | 1.4 |
| **5,000 (chosen)** | **~10 MB** | **~13.7** |
| 10,000 | ~20 MB | ~27.4 |
| 50,000 | ~100 MB | ~137 |

Real-world generation rates are user-action-bounded:

| User profile | Records/year |
|---|---|
| Opens daily, never warps | 365 |
| Daily + occasional warp | ~420 |
| Heavy warper (5 days/week explored) | ~620 |
| Wheel power user (every day, every visit) | ~700–800 |

A user would need >6 years of obsessive warping to hit 5,000 records. The threshold is comfortable headroom for any realistic usage — it functions as a safety valve, not a routine cleanup.

### 11.4 Why the threshold isn't user-configurable

For V1 the policy is fixed. A user-facing "keep briefs for N days/months/forever" setting is speculative scope: the data is small enough that no real user is asking for it, and adding it expands surface area in Settings. If we ever see real complaints, this can be added without schema change — just expose the constants through `UserPreferences`.

### 11.5 What this pattern looks like for other regenerable models

When future regenerable models land (FM-summarized week recaps, extracted task lists, page-level OCR caches), they should each:

1. Declare retention class explicitly — class membership goes in the EDD entry for the model.
2. Carry their own `lastAccessedAt`.
3. Define their own `evictionThreshold` + `evictionTarget` + `touchInterval` static constants.
4. Trigger eviction at their write path, not a periodic job.
5. Document the policy in this section.

Authored models never need any of this — they have no eviction, by definition.

### 11.6 What's deliberately *not* in V1

- Compression on persist (records are ~2 KB; gzipping prose has poor ROI).
- Tiered sync (hot vs warm vs cold SwiftData containers).
- Aggregation / summarization of old briefs into weekly/monthly digests.
- User-facing retention settings.
- Background-task-based eviction.

Each is documented as a known future option but not implemented. The combination of (a) small records, (b) LRU at a generous threshold, and (c) cloud-native regenerability means these aren't load-bearing for V1.

---

## 12. Open Questions

| # | Question | Impact |
|---|---|---|
| 1 | Should internal links (`targetPageID`) use a SwiftData relationship instead of a UUID? | Relationships auto-resolve and cascade, but cross-notebook link deletion becomes risky. Current design favors UUID with runtime resolution. |
| 2 | Should `NoteHistoryEntry` fully replace `RoutedItem`, or do both coexist? | `RoutedItem` tracks dispatch status ("sent", "deleted", "completed"). History entries are immutable records. They may serve different purposes. |
| 3 | Should `NoteLink` support linking to a specific header on a target page? | Would need an optional `targetHeaderID: UUID?` field. Not needed for v1 but worth considering since CloudKit schema changes are additive only after production deploy. |
| 4 | What is the maximum number of pages per notebook? | Affects sync performance and UI. If unbounded, we may need lazy page loading. |
| 5 | OCR text strategy — flat string or structured regions? | `ocrText: String?` works for v1 search but loses bounding boxes. If we want "tap a search result and jump to that region on the page," we need a richer structure — probably a `TextRegion` sub-model with x/y/width/height per recognized chunk. Deferring until search UX is designed, but the migration won't be free. |
| 6 | Custom templates — string reference or `Template` model? | `templateName: String` refers to built-ins today. Custom templates (user-created) would need either a `Template` model with `imageData` or a folder convention on disk. A `Template` model syncs via CloudKit; a folder convention doesn't. |
| 7 | Folder deletion semantics — should cascading to notebooks be an option? | Current design nullifies (moves to root). reMarkable cascades folder deletions. Worth confirming with UX. |
