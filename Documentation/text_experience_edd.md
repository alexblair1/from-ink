# EDD — Premium Note-Taking Experience (Hybrid Text + Ink + Voice)

| Field | Value |
|---|---|
| Status | Approved — ready to implement |
| Owner | Solo |
| Last updated | 2026-06-08 |
| Implements ticket | F-20 (Text experience) |
| Companion docs | EDD — View Layer · EDD — Data Layer · EDD — Data Model · EDD — Toolbar · EDD — Design System · EDD — Dates · EDD — Localization |

---

## Table of contents

1. [Summary](#1-summary)
2. [Goals & non-goals](#2-goals--non-goals)
3. [Capability matrix — devices × inputs](#3-capability-matrix--devices--inputs)
4. [Architecture overview](#4-architecture-overview)
5. [The document model — blocks](#5-the-document-model--blocks)
6. [Canvas geometry — canonical units & viewport scaling](#6-canvas-geometry--canonical-units--viewport-scaling)
7. [SwiftData persistence](#7-swiftdata-persistence)
8. [CloudKit translation](#8-cloudkit-translation)
9. [Schema changes](#9-schema-changes)
10. [The drag bar — block height UX](#10-the-drag-bar--block-height-ux)
11. [Region anchors — ink rect vs text range](#11-region-anchors--ink-rect-vs-text-range)
12. [Highlights — defaults & custom kinds](#12-highlights--defaults--custom-kinds)
13. [Slash command palette](#13-slash-command-palette)
14. [Text editing chrome per platform](#14-text-editing-chrome-per-platform)
15. [Pencil ↔ keyboard handoff on iPad](#15-pencil--keyboard-handoff-on-ipad)
16. [Selection menu extensions](#16-selection-menu-extensions)
17. [Keyboard shortcut inventory](#17-keyboard-shortcut-inventory)
18. [Voice-to-text architecture](#18-voice-to-text-architecture)
19. [Accessibility & inclusive design](#19-accessibility--inclusive-design)
20. [Localization](#20-localization)
21. [Testing strategy](#21-testing-strategy)
22. [Refactor plan](#22-refactor-plan)
23. [Open questions](#23-open-questions)
24. [Decision log](#24-decision-log)

---

## 1. Summary

This EDD specifies the premium note-taking experience: a hybrid surface where typed text, Apple Pencil ink, and voice memos coexist on the same page, work across iPad / iPhone / Mac, and meet a level of accessibility worth an Apple Design Award.

The architecture rests on five load-bearing decisions:

1. **A page is an ordered list of blocks** (`text` | `ink` | `voice`), not a single buffer. Hybrid composition becomes a sort-order over typed records, not a layout puzzle inside a flat document.
2. **SwiftUI `TextEditor` + `AttributedString`** is the text engine on every platform (iOS 26 rich text APIs). `AttributedString` is the persisted form. If a load-bearing capability (custom attribute round-trip, caret rect for slash anchoring, selection-menu extension) fails the spike, fall back to a `UIViewRepresentable` wrapping `UITextView` over TextKit 2 — same data shape, more code.
3. **`NoteRegion` carries an anchor discriminator** (`.inkRect` | `.textRange`). One dispatch panel, one set of badges, one lifecycle — text-anchored regions ride on an `AttributedString` custom attribute so they move with text edits for free.
4. **A canonical canvas (768pt wide) is the storage coordinate space for ink.** Every viewport renders at `viewport.width / 768` scale. Portrait→landscape, iPad→iPhone, iPad→Mac collapse to the same scaling rule.
5. **The reducer-action vocabulary IS the command vocabulary.** Voice Control, Switch Control, slash menu, accessory bar, keyboard shortcuts, and menu bar entries all dispatch the same actions. One reducer, many chromes.

The whole experience is modular: each block kind is a separate component, each chrome is a separate view, each platform is a separate wiring layer. No component knows what device it's on; the wiring layer decides.

This EDD supersedes nothing; it extends the data model EDD (block model), the view layer EDD (text editor + accessory bar tiers), the toolbar EDD (text-mode toolbar variants), and the design system EDD (contrast + Dynamic Type rules) with the rules a hybrid editor needs.

---

## 2. Goals & non-goals

### Goals

- A single page can carry typed text, ink, and voice memos in any order, on iPad. Other platforms render everything and author what they can.
- Authoring works on iPad (text + ink + voice), iPhone (text + voice), Mac (text + voice). Ink is read-only on iPhone and Mac.
- Handwriting authored on any device renders consistently on every other device under one scaling rule.
- The slash menu (`/`) and the iPhone accessory bar are two presentations of the same command vocabulary, picked by input source.
- Every reducer action that affects the document is invokable via VoiceOver, Voice Control, Switch Control, and at least one of {keyboard shortcut, menu bar entry, accessory bar tap}.
- Voice-to-text is a first-class capture surface, not just system dictation.
- Region anchors survive text edits without manual offset tracking.
- The block model degrades gracefully under CloudKit's per-record size limit (1 MB) because each block is one CKRecord.
- VoiceOver reading order is the block order with no inference.

### Non-goals

- This EDD does not specify the existing ink-only canvas pipeline (PKDrawing recording, OCR debouncing, stroke persistence) — those are unchanged from `CanvasView` and continue to apply within ink blocks. See `CLAUDE.md` "Canvas + TCA boundary" and the toolbar EDD §3.2.
- This EDD does not redesign the dispatch flow. `DispatchFeature` continues to back the universal Dispatch modal; text-selection dispatch routes through the same reducer with a different seed.
- This EDD does not solve real-time collaboration. CloudKit LWW per block is the chosen merge model; multi-cursor / CRDT is an open question.
- This EDD does not define the home-screen voice capture UI in pixel detail. It specifies the surface and the state machine; the visual design is a follow-up artifact.
- This EDD does not cover PDF annotation or the PDF viewer — those remain owned by `PDFFeature`.

---

## 3. Capability matrix — devices × inputs

| Capability | iPad regular | iPad compact (Slide Over) | iPhone | Mac |
|---|---|---|---|---|
| Render ink | ✅ | ✅ | ✅ | ✅ |
| Author ink | ✅ (Pencil) | ✅ (Pencil if available) | ❌ | ❌ |
| Render text | ✅ | ✅ | ✅ | ✅ |
| Author text | ✅ | ✅ | ✅ | ✅ |
| Render voice memos | ✅ | ✅ | ✅ | ✅ |
| Record voice memos | ✅ | ✅ | ✅ | ✅ |
| Slash menu popover | ✅ | ✅ (when hardware keyboard connected) | ❌ (no hardware kbd path) | ✅ |
| Accessory bar | ✅ (soft keyboard only) | ✅ (soft keyboard only) | ✅ | ❌ |
| Region creation gesture | Pencil two-finger hold OR selection menu | Selection menu | Selection menu | Right-click |
| Drag bar (ink block height) | ✅ | ❌ | ❌ | ❌ |
| Keyboard shortcuts | ✅ (hardware kbd) | ✅ (hardware kbd) | ✅ (hardware kbd) | ✅ |

**Hardware keyboard rule.** A hardware keyboard ALWAYS gets the slash menu, regardless of size class. The soft-keyboard accessory bar hides automatically when a hardware keyboard connects (UIKit's existing behaviour). So the matrix above is shorthand for two intermediate rules:

- Slash menu shows when EITHER `horizontalSizeClass == .regular` OR a hardware keyboard is connected.
- Accessory bar shows when the soft keyboard is up AND no hardware keyboard is connected.

This closes the iPad-compact-with-hardware-keyboard gap (where neither surface would otherwise have been available).

**Two device classes for input purposes:**

- **iPad regular** — full authoring (ink + text + voice). The only place ink is mutable.
- **iPhone + Mac + iPad compact** — render-everywhere, text-and-voice authoring, ink is read-only.

The compact size class on iPad is treated as iPhone, not iPad. The gate is `horizontalSizeClass`, not the device family.

---

## 4. Architecture overview

```
NotebookFeature
  └─ pages: [NotePageSnapshot]
       └─ NotePageFeature (NEW — replaces per-page state in CanvasScreen)
            ├─ blocks: IdentifiedArrayOf<PageBlockSnapshot>
            ├─ activeBlockID: UUID?
            ├─ Scope(state: \.textEditing,     action: \.textEditing)
            │     └─ TextEditingFeature (NEW)
            │          └─ slashPalette: SlashCommandPaletteFeature (NEW)
            ├─ Scope(state: \.toolbar,         action: \.toolbar)
            │     └─ ToolbarFeature (existing — gains text-mode zone config)
            └─ Scope(state: \.voiceCapture,    action: \.voiceCapture)
                  └─ VoiceCaptureFeature (NEW)
```

### View tiers

Per the view layer EDD §4, every view is one of three tiers. The boundary is the `ComposableArchitecture` import.

| View | Tier | Imports TCA | Notes |
|---|---|---|---|
| `TextBlockView` | Component | No | SwiftUI `TextEditor` with `AttributedString` (iOS 26 rich text APIs); UIKit `UITextView` bridge as fallback if a custom-attribute capability is missing. |
| `InkBlockView` | Component | No | PKCanvasView wrapper at canonical scale; same imperative boundary as today's `CanvasView` |
| `VoiceBlockView` | Component | No | Audio player + transcript editor |
| `DragBarView` | Component | No | The handle between blocks; emits height changes via closure |
| `SlashMenuPopoverView` | Component | No | Caret-anchored popover for Mac + iPad regular |
| `SlashMenuDockedView` | Component | No | (Unused — iPhone uses `TextAccessoryBarView` instead. Kept in §13 as a future option.) |
| `TextAccessoryBarView` | Component | No | Mode-switching single-row bar above keyboard |
| `AaFormatPopoverView` | Component | No | Multi-row block/inline format popover above the accessory bar |
| `RegionIndicator` | Component | No | Existing — extended to render text-range indicators |
| `PageBlockStackView` | Feature | No | Stacks blocks vertically with drag bars between |
| `NotePageView` | Feature | No | Composes block stack + chrome |
| `NotePageWiringView` | Wiring | Yes | Owns the Store, converts to Model, hosts platform-specific chrome |

### Modularity contract

Each block kind is a self-contained component with three responsibilities:
1. Render the block's payload at the block's `heightPoints * viewportScale`.
2. Expose a `Model` with all visual + accessibility fields resolved by an adapter.
3. Emit user intents via closures — never own state, never touch the Store.

A future fourth block kind (`pdf` page embed, `image`, `embed`) plugs in by adding one enum case to `PageBlockKind`, one component, one adapter. Nothing else changes.

---

## 5. The document model — blocks

A page is an ordered list of blocks. Each block is a typed record with one payload.

```swift
enum PageBlockKind: String, Codable, CaseIterable, Sendable {
    case text
    case ink
    case voice
    // Planned for v1.1 — architecture supports the addition; adding a
    // new kind is one enum case + one component + one adapter, no
    // changes to the block stack, persistence, or sync layers.
    //   case image
    //   case video
}
```

### 5.1 `PageBlock` schema

```swift
@Model final class PageBlock {
    var id: UUID = UUID()
    var page: NotePage? = nil
    var sortIndex: Int = 0
    var kindRaw: String = PageBlockKind.text.rawValue
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Canonical-canvas-space height. For text blocks, this is the
    /// last laid-out height cached at write time (recomputed on every
    /// render). For ink and voice blocks, it is user-adjustable via
    /// the drag bar (ink) or fixed by content (voice).
    ///
    /// All viewport sizing is `heightPoints * viewportScale` — see §6.
    var heightPoints: Double = 200

    // MARK: Text payload
    /// Archived `AttributedString` (NSKeyedArchiver of NSAttributedString
    /// bridged from AttributedString). externalStorage → CKAsset on sync.
    @Attribute(.externalStorage) var bodyData: Data? = nil

    /// Queryable plain-text mirror. Recomputed on every save. Drives
    /// `#Predicate` search, FM input, OCR cache invalidation.
    var plainText: String? = nil

    // MARK: Ink payload
    /// PKDrawing data in canonical-canvas coordinates. externalStorage → CKAsset.
    @Attribute(.externalStorage) var drawingData: Data? = nil
    @Attribute(.externalStorage) var thumbnailData: Data? = nil
    var ocrText: String? = nil
    var ocrUpdatedAt: Date? = nil

    // MARK: Voice payload
    /// m4a audio (AAC). externalStorage → CKAsset. Nil on Mac/iPhone
    /// while transcript-only mode is in flight (not v1).
    @Attribute(.externalStorage) var audioData: Data? = nil
    /// Transcript captured by `SpeechService`. User-editable post-capture.
    /// Persists the transcript even if audio is later cleared.
    var transcript: String? = nil
    var transcriptConfidence: Double = 0
    var audioDurationSeconds: Double = 0
    /// BCP-47 — the locale active at capture time. Locked so re-transcription
    /// later (e.g., user changes language) doesn't replace authoritative text.
    var transcriptLanguage: String? = nil

    init(
        id: UUID = UUID(),
        page: NotePage? = nil,
        sortIndex: Int = 0,
        kind: PageBlockKind = .text,
        heightPoints: Double = 200
    ) {
        self.id = id
        self.page = page
        self.sortIndex = sortIndex
        self.kindRaw = kind.rawValue
        self.heightPoints = heightPoints
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    var kind: PageBlockKind {
        get { PageBlockKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }
}
```

### 5.2 `NotePage` extensions

```swift
@Model final class NotePage {
    // ... existing fields

    @Relationship(deleteRule: .cascade, inverse: \PageBlock.page)
    var blocks: [PageBlock]? = []

    /// Aggregated extracted text: `text.plainText ∪ ink.ocrText ∪ voice.transcript`,
    /// joined in `sortIndex` order. Drives full-text search, FM input, and
    /// VoiceOver "read entire page" composition.
    var extractedText: String? = nil
    /// Aggregated hash. Composed from per-block `contentHash` values (see
    /// §7.5) rather than hashed off `extractedText` directly, so block
    /// reorders don't trip ML cache invalidation when no content actually
    /// changed.
    var extractedTextHash: String = ""
}
```

The legacy `NotePage.drawingData` and `NotePage.ocrText` fields are deleted in the same commit that adds the block model (no migration — see §9).

### 5.3 Text content — the block-tree document

> **Architectural decision (2026-06-09).** A Text PageBlock's content is a
> **`RichTextDocument` (block tree)**, not a single `AttributedString`. The
> decision was forced by what manual testing exposed:
>
> 1. Apple's `TextEditor` (SwiftUI, iOS 26) does not paint `PresentationIntent`
>    block-level kinds — headings, lists, blockquote, codeBlock,
>    thematicBreak all persist semantically but render as plain prose.
> 2. `UITextView(usingTextLayoutManager: true)` (TextKit 2) has the same
>    behavior — confirmed by a verbatim swap in the production editor.
> 3. The custom-`NSLayoutManager` path requires **TextKit 1** —
>    `drawBackground(forGlyphRange:at:)` only fires under
>    `NSLayoutManager`, never under `NSTextLayoutManager`. PoC verified
>    2026-06-09: a hand-built TextKit 1 stack with a `BlockDecoratingLayoutManager`
>    subclass DOES paint block-level chrome.
>
> A block tree expressed as a rigid Codable schema (ProseMirror-style) lets us
> map each block kind to its own visual treatment — either as its own
> SwiftUI view at the page level or as a paragraph-with-blockType-tag inside
> the Text PageBlock's UITextView. `PresentationIntent` is dropped as the
> in-storage representation; it is **not used** anywhere in the From Ink data
> model going forward.

#### The schema

```swift
struct RichTextDocument: Codable, Equatable, Sendable {
    /// Migration anchor — every encoded document carries the schema
    /// version it was written under. Decoder dispatches on this to
    /// translate older shapes forward. SwiftData migrations stay
    /// schema-flat; content shape migrations live HERE.
    var version: Int

    /// Ordered list of top-level blocks. Empty array is a valid
    /// document (an empty block).
    var blocks: [Block]
}

/// `indirect` because containers hold child blocks. Codable conformance
/// is hand-written — synthesised CodingKeys for an `indirect enum`
/// produce a shape SwiftData destructures incorrectly when stored as
/// a typed property. We never hand SwiftData this type directly — only
/// the encoded `Data` blob (see §7.3).
indirect enum Block: Codable, Equatable, Sendable {
    case paragraph(inline: [Inline])
    case heading(level: Int, inline: [Inline])       // level 1...3
    case codeBlock(text: String, languageHint: String?)  // leaf — no marks
    case bulletList(items: [ListItem])
    case orderedList(items: [ListItem])
    case blockquote(children: [Block])               // container
    case divider                                     // leaf — no payload
}

struct ListItem: Codable, Equatable, Sendable {
    /// A list item holds one or more blocks. The first is always a
    /// paragraph; subsequent blocks (typically a nested list) are
    /// optional. Codable verifies this invariant on decode.
    var content: [Block]
}

struct Inline: Codable, Equatable, Sendable {
    var text: String
    var marks: [Mark]
}

/// Inline emphasis. Add cases as the editor grows; the decoder is
/// lenient — unknown future cases are dropped from the inline run
/// rather than throwing, so a v1 client opening a v2 document keeps
/// the text and only loses the unfamiliar emphasis.
enum Mark: Codable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case highlight(HighlightKind)
    case link(URL)
}

enum HighlightKind: String, Codable, Hashable, Sendable {
    case yellow, red, blue, green
}
```

#### Containment rules

The schema's invariants — enforced by Codable conformance and the
reducer:

| Block | Role | May contain |
|---|---|---|
| `paragraph` | leaf | inline runs |
| `heading(level:)` | leaf | inline runs |
| `codeBlock` | leaf | plain text only (no marks) |
| `bulletList` / `orderedList` | container | `[ListItem]` |
| `listItem` | container | first child is `paragraph`, optional second is nested list |
| `blockquote` | container | any blocks |
| `divider` | leaf | nothing |

These rules are the schema's heart. A rigid containment table is what
makes the editing UX feel flexible — every valid edit produces a valid
tree; invalid states are unreachable.

### 5.4 Block snapshot (value type for TCA State)

Per `CLAUDE.md` and the data layer EDD, `@Model` objects never enter TCA `State`. The reducer reads `PageBlockSnapshot`:

```swift
struct PageBlockSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let sortIndex: Int
    let kind: PageBlockKind
    let heightPoints: Double

    // Payload — at most one of these is populated
    let document: RichTextDocument?    // for .text blocks
    let drawingData: Data?              // for .ink blocks
    let voice: VoiceSnapshot?           // for .voice blocks

    /// Backreference for Voice → Transcript flow (§18 scenario C). The
    /// text block created from a transcribed voice block carries the
    /// source voice block's ID so the reader can play the original.
    let sourceVoiceBlockID: UUID?

    struct VoiceSnapshot: Equatable, Sendable {
        let audioURL: URL?
        let transcript: String
        let transcriptConfidence: Double
        let durationSeconds: Double
        let language: String?
    }
}
```

`RichTextDocument` is a value type with synthesised `Equatable` — safe and cheap to compare in `State`. `Data` for `drawingData` is large; the snapshot path keeps a copy only while the active block is being edited. Inactive blocks hold a snapshot with `drawingData == nil` and resolve lazily via the `NotebookClient` when scrolled into view.

**Equality cost.** `RichTextDocument.Equatable` is O(n) over blocks + inline runs. Typical note-taking workloads (one block holding one paragraph to one page of text, hundreds of inline runs at most) compare in well under 1ms. **Threshold:** if a block's encoded `bodyData` exceeds 50 KB, switch the snapshot to a hash-based equality wrapper — store `document` alongside a precomputed `documentHash: UInt64`, and define `==` as `documentHash == documentHash`. Until that threshold trips in profiling, the direct comparison ships.

### 5.5 PageBlock kind invariants

| Block kind | `bodyData` | `drawingData` | `audioData` | Notes |
|---|---|---|---|---|
| `.text` | required (JSON of `RichTextDocument`; may be an empty document with `blocks: []`) | nil | nil | `plainText` mirror always present, derived from inline runs |
| `.ink` | nil | required (may be empty `PKDrawing`) | nil | `ocrText` populated by OCR service |
| `.voice` | nil | nil | required during capture; may be cleared post-capture to keep transcript-only | `transcript` required |

The reducer enforces these invariants at the API boundary (`NotebookClient.insertBlock`, `updateBlock`). The data model doesn't enforce them — CloudKit-compatible storage means all fields are optional with defaults; the application layer is responsible for the at-most-one rule, same pattern as `NoteRegion`'s link target.

---

## 6. Canvas geometry — canonical units & viewport scaling

The cross-platform handwriting problem is solved by a single rule: **ink is stored in canonical-canvas coordinates; rendering applies `viewport.width / canonicalWidth` as a scale factor.**

### 6.1 The canonical canvas — per-notebook

Canonical width is per-notebook, **set on first ink stroke** to the authoring device's portrait width. iPad Pro 13" portrait records 1024pt; iPad 11" portrait records 834pt; iPad mini records 744pt. A new notebook with no ink yet defaults to 768pt; the value snaps to the authoring device on first stroke and never changes after.

```swift
@Model final class Notebook {
    // ... existing fields

    /// Canonical canvas width for ink coordinates in this notebook.
    /// Defaults to 768pt; bound on first stroke to the authoring
    /// device's portrait width via `NotebookClient.bindCanonicalWidth(_:)`.
    /// Never changes after the binding is set.
    var canonicalCanvasWidth: Double = 768
}

enum CanvasGeometry {
    /// Default canonical width for brand-new notebooks before any ink
    /// lands. iPad portrait 11" reads as the cleanest default — iPad
    /// users author at near-1:1; smaller devices scale down slightly;
    /// larger devices scale up slightly.
    static let defaultCanonicalWidth: CGFloat = 768

    /// Minimum scale factor. Below this, content overflows horizontally
    /// and the viewport adds a horizontal scroll affordance rather than
    /// rendering unreadably small ink.
    static let minScale: CGFloat = 0.5

    /// Maximum scale factor for hybrid pages (pages with at least one
    /// text block). Caps the proportion mismatch between scaled ink
    /// and Dynamic-Type-sized text. Pure-ink pages have no cap.
    static let hybridMaxScale: CGFloat = 1.5

    /// Compute the scale factor for a viewport width on a given page.
    /// `canonicalWidth` is read from the notebook (see §6.1) — never
    /// hardcoded to `defaultCanonicalWidth` at the call site.
    static func scale(
        viewportWidth: CGFloat,
        canonicalWidth: CGFloat,
        hasTextBlocks: Bool
    ) -> CGFloat {
        let raw = viewportWidth / canonicalWidth
        let cap = hasTextBlocks ? hybridMaxScale : .greatestFiniteMagnitude
        return min(max(raw, minScale), cap)
    }
}
```

### 6.2 Why per-notebook canonical width

A per-notebook canonical width makes the authoring experience deviceless: a user authoring on iPad Pro 13" draws at 1:1 on their own device, not at 1.33× of someone else's canonical assumption.

- **Authoring is always 1:1.** No matter what device created the notebook, that device renders at scale 1.0.
- **Cross-device anchors are stable.** `NoteRegion.rectX/Y/W/H` are canonical-space units. A region at (100, 200) is at (100, 200) everywhere — the rendering scale changes, the data doesn't.
- **OCR is computed once.** OCR runs against the canonical drawing; the result is the same regardless of viewport.
- **Portrait → landscape is a viewport change, not a data change.** No re-flow, no re-write.

The alternative — normalized 0-1 coordinates — has the same theoretical properties but PencilKit doesn't natively support normalized units. We'd be transforming on every read and write. Canonical points are PencilKit-native.

### 6.3 Rendering scale per viewport

```
iPad portrait     768pt   →  scale 1.00   (1:1, the canonical)
iPad landscape    1024pt  →  scale 1.33
iPad portrait + Magic Keyboard floating  728pt  →  scale 0.95
iPhone Pro Max portrait    430pt   →  scale 0.56
iPhone mini portrait       360pt   →  scale 0.50  (at minScale floor)
Mac window 1200pt wide     →  scale 1.56  (hybrid cap: 1.50)
Mac window 1600pt wide     →  scale 2.08  (hybrid cap: 1.50; pure-ink: 2.08)
```

### 6.4 Implementation — PKCanvasView at canonical size, container scaled

```swift
// InkBlockView (component)
//
// PKCanvasView's bounds are set to canonical width × heightPoints (in
// canonical units). The view records strokes in canonical coordinates
// natively. A container view applies `CGAffineTransform(scaleX: scale, y: scale)`
// to render at viewport size. Touches arrive at the container, are
// translated through the inverse transform, and reach PencilKit at
// canonical coordinates — so PKDrawing storage is unchanged from today.
//
// Performance: the GPU does the scale; PencilKit sees a fixed-size
// canvas. No per-frame redraws on rotation — only the container's
// transform changes.

struct InkBlockView: View {
    let model: Model

    var body: some View {
        InkCanvasRepresentable(
            drawingData: model.drawingData,
            tool: model.tool,
            penSettings: model.penSettings,
            canonicalSize: CGSize(width: model.canonicalWidth,
                                   height: model.heightPoints),
            onDrawingChanged: model.onDrawingChanged,
            onLassoReady: model.onLassoReady
        )
        .frame(width: model.canonicalWidth, height: model.heightPoints)
        .scaleEffect(model.scale, anchor: .topLeading)
        .frame(width: model.canonicalWidth * model.scale,
               height: model.heightPoints * model.scale)
        .accessibilityElement()
        .accessibilityLabel(model.accessibilityLabel)
    }
}
```

### 6.4.1 Per-block ink lifecycle (canvas pooling)

A single `PKCanvasView` is ~4 MB resident (Metal layer, predicted-touch buffers, palm rejection state) plus the loaded `PKDrawing`. A 20-ink-block page with all-live canvases lands ~80 MB; a 50-block page lands ~200 MB. On iPad mini / base iPad this is hostile. The fix: only blocks that are on-screen or actively edited own a live `PKCanvasView`; off-screen blocks render as static images from `thumbnailData`.

Each ink block sits in one of three states:

```swift
enum InkBlockLoadState: Equatable {
    /// Far off-screen. Render nothing — just reserve scroll space equal
    /// to (heightPoints × scale). No drawing loaded, no PKCanvasView,
    /// no thumbnail in memory.
    case placeholder

    /// Off-screen but in warm range, OR on-screen but not actively
    /// edited. Render a static UIImage from thumbnailData. No
    /// PKCanvasView. Scroll-into-view promotes to .live.
    case thumbnail(UIImage)

    /// Has a live PKCanvasView. Strokes record into it. The only state
    /// in which authoring is possible.
    case live(drawingData: Data)
}
```

**Range policy.** `PageBlockStackView` tracks viewport intersection per block and feeds visibility into the reducer:

| Range | Definition | State |
|---|---|---|
| Active range | Visible in viewport + 1 block above + 1 below | `.live` |
| Warm range | Active range + 2 blocks above + 2 below | `.thumbnail` |
| Cold | Everything else | `.placeholder` |
| Editing override | The currently-active block (`activeBlockID`) | `.live` regardless of viewport |

**Memory math.** Same 50-block page, editing one block: 3 live ink blocks (~12 MB) + 4 thumbnails (~1 MB) + 43 placeholders (~0 MB) = ~13 MB total, down from ~200 MB. Memory scales with what's visible, not page length.

**Reducer actions** (on `NotePageFeature`):

```swift
case blockEnteredActiveRange(UUID)
case blockExitedActiveRange(UUID)
case blockEnteredWarmRange(UUID)
case blockExitedWarmRange(UUID)
case blockDrawingLoaded(UUID, Data)
case blockThumbnailRendered(UUID, UIImage)
case blockActivated(UUID)
```

**Edge cases:**

- **Rapid scroll thrashing.** Debounce `.live` promotions by 100ms. Thumbnails render instantly from disk.
- **Active block scrolled off-screen.** Stays `.live` while it's `activeBlockID`. Demotes only when the user dismisses the keyboard or activates another block.
- **First-load.** Every block starts as `.placeholder`; on appearance the visibility signal fires `.blockEnteredActiveRange` and the reducer loads `drawingData`. A `.thumbnail` fallback rendered from `thumbnailData` covers the one-frame load gap.
- **Stale thumbnail after demote.** Demoting `.live → .thumbnail` renders a fresh thumbnail from the current PKDrawing via the existing `CanvasViewBridge` snapshot path, replacing `thumbnailData`.
- **Newly-inserted ink block.** Starts `.live` (user just created one to draw in). If they scroll away before drawing anything, the demote produces an empty-canvas thumbnail.
- **Text and voice blocks.** Don't need this lifecycle. `TextKit 2` is lighter (~500 KB per block) and `AVAudioPlayer` is tiny. Lifecycle is ink-only.

**Persistence boundary.** The existing `CanvasViewBridge` pattern moves to per-block. `NotePageFeature` state holds a `[UUID: CanvasViewBridge]` for live blocks. Transitions that flush:
- `.live → .thumbnail` demotion
- Active block changes
- Page swipe (existing `onDisappear`)
- Scene phase backgrounded (existing hook)

The flush logic itself (`snapshotForFlush()` → `CanvasViewBridge.persist(snapshot)`) is unchanged from today; only the cardinality changes from one-per-page to many-per-page.

**Visibility signal.** iOS 17+'s `onScrollVisibilityChange(threshold:)` provides the per-child intersection callback. `PageBlockStackView` wires it on each block row; warm-range tracking extends the threshold or is computed in the reducer as "active range ± 2 blocks."

### 6.5 Text blocks are decoupled from ink scale

Text reflows to viewport width using Dynamic Type. **Text size is not affected by canvas scale.** A consequence: on iPhone, scaled-down ink coexists with full-sized text. This is intentional — text always optimizes for reading; ink renders "as written." This matches Apple Notes.

A pure-ink page on a Mac at 1600pt scales ink to 2.08×. A hybrid page on the same Mac caps at 1.50× to preserve the typographic relationship.

### 6.6 Portrait → landscape on iPad

Pure viewport change. The container's `scaleEffect` updates from `1.00` to `1.33`; the block stack relayouts because text blocks have new widths (and new heights from reflow); ink blocks render at new scale; voice blocks expand horizontally to fill. No data writes.

State to preserve across rotation: scroll position (express as fraction of total page height, not absolute), active block selection, caret position within a text block, current `accessoryMode`.

### 6.7 Cross-platform handwriting — the unified rule

| Authored on | Opened on | Scale | Visual result |
|---|---|---|---|
| iPad portrait | iPad portrait | 1.00 | Identical |
| iPad portrait | iPad landscape | 1.33 | Larger, fills width |
| iPad landscape | iPad portrait | 0.75 | Smaller, fits width |
| iPad | iPhone | 0.50–0.56 | Compressed but readable |
| iPad | Mac (window-dependent) | 1.00–2.08 | Scales with window |
| iPhone (if Pencil ever existed) | iPad | 1.78 | Larger |

One rule, every direction.

---

## 7. SwiftData persistence

All CloudKit-friendly rules from the data model EDD and `CLAUDE.md` continue to hold. The block model is purely additive.

### 7.1 Property checklist

Every `PageBlock` property is optional or defaulted:

| Property | Default | CloudKit-safe |
|---|---|---|
| `id` | `UUID()` | ✅ |
| `page` | `nil` | ✅ relationship optional |
| `sortIndex` | `0` | ✅ |
| `kindRaw` | `"text"` | ✅ |
| `createdAt` / `modifiedAt` | `Date()` | ✅ |
| `heightPoints` | `200` | ✅ |
| `bodyData` / `drawingData` / `thumbnailData` / `audioData` | `nil` | ✅ externalStorage → CKAsset |
| `plainText` / `ocrText` / `transcript` | `nil` | ✅ |
| `ocrUpdatedAt` | `nil` | ✅ |
| `transcriptConfidence` / `audioDurationSeconds` | `0` | ✅ |
| `transcriptLanguage` | `nil` | ✅ |

No `@Attribute(.unique)`. Application layer enforces ID uniqueness via `IdentifiedArray`.

### 7.2 Relationships

```swift
// On NotePage (parent — declares the macro):
@Relationship(deleteRule: .cascade, inverse: \PageBlock.page)
var blocks: [PageBlock]? = []

// On PageBlock (child — plain back-pointer, NO macro):
var page: NotePage? = nil
```

Same pattern as `NoteHeader`, `NoteLink`, `NoteRegion`. Avoids SwiftData's "duplicate inverse" runtime error.

### 7.3 RichTextDocument serialization

`PageBlock.bodyData: Data?` stores **`JSONEncoder().encode(richTextDocument)`** — never an `AttributedString`. The block tree's `Codable` conformance is the only persistence boundary; SwiftData treats `bodyData` as opaque bytes, sidestepping the recursive-Codable destructuring crash that ships when a polymorphic `indirect enum` is handed to SwiftData as a typed property.

```swift
// Encode
let data = try JSONEncoder().encode(snapshot.document)

// Decode
let document = try JSONDecoder().decode(RichTextDocument.self, from: data)
```

**Versioning.** `RichTextDocument.version: Int` is checked on every decode. The decoder dispatches on the value to translate older shapes forward — content-shape migrations live here, NOT in SwiftData's `VersionedSchema`. Because the encoded JSON is opaque to SwiftData, the @Model schema can stay flat across content evolutions.

**Forward compatibility.** The `Mark` decoder is lenient: cases it doesn't recognise (a v2 mark a v1 client opens) are dropped from the inline run, but the surrounding `text` survives. The user sees plain text where the unknown emphasis would have been, never a broken document. The same lenience applies to unknown `Block` cases — they decode as a `paragraph` carrying the failed block's textual content as a single inline run, preserving the user's words.

**Path A (`NSKeyedArchiver` of `NSAttributedString`) and Path B (`JSONEncoder` of `AttributedString`) are both deleted.** Neither survives the block-tree pivot. Existing `PageBlockSnapshot.encodeBody` and `decodeBody` helpers continue to exist as the single encode/decode boundary, but their internals switch to the JSON-of-RichTextDocument path. Tests pin the round-trip.

### 7.4 Marks — the inline emphasis vocabulary

Replacing the prior `FromInkAttributes` `AttributedString` scope, inline emphasis is now expressed via the `Mark` enum (§5.3). The vocabulary at v1:

| Mark | Visual at v1 | Inline-only? |
|---|---|---|
| `.bold` | semibold weight | yes |
| `.italic` | italic style | yes |
| `.underline` | single underline | yes |
| `.strikethrough` | single strikethrough | yes |
| `.code` | monospaced span, soft tint | yes |
| `.highlight(HighlightKind)` | colored span background | yes |
| `.link(URL)` | underlined accent foreground, tap routes via deep-link handler | yes |

**Adding a mark.** Three steps: add the enum case to `Mark`; teach the editor renderer (UITextView's attribute conversion) how to map it; teach the slash-menu / selection-menu UI how to apply it. The decoder is forward-compatible — the new case appears in v(n+1) clients automatically without breaking v(n).

**Region anchors no longer live in inline marks.** A NoteRegion that anchors to a span of text addresses the span by **block path + character offset** (see §11), not by a `regionAnchor` attribute on an `AttributedString`. The `RegionAnchorAttribute` / `HighlightAttribute` / `SlashInsertionAttribute` AttributedString-scope keys are deleted along with the prior `AttributeScopes.FromInkAttributes` story; `HighlightKind` survives as the payload of `Mark.highlight`.

### 7.5 Per-block content hash

`PageBlock` carries a `contentHash: String` field. `NotePage.extractedTextHash` is computed by hashing the concatenation of the per-block `contentHash` values in `sortIndex` order — not by hashing the joined `extractedText` directly.

```swift
@Model final class PageBlock {
    // ... existing fields

    /// SHA256 of the block's authoritative content:
    ///   .text  → plainText
    ///   .ink   → ocrText (or empty when OCR hasn't run)
    ///   .voice → transcript
    /// Recomputed on every block save. Drives NotePage.extractedTextHash.
    var contentHash: String = ""
}
```

**Why this shape:**

- Reordering blocks changes `NotePage.extractedTextHash` (sort-order is part of the manifest), so ML output keyed to the old order can refresh.
- Editing one block changes only that block's `contentHash`; the page hash changes too, but Foundation Models / summarization can elect to reprocess only the deltas by diffing the per-block manifest from the last run.
- Without the per-block hash, every reorder would trip a full FM re-run even when no content changed.

The page-level hash composition:

```swift
extension NotePage {
    func recomputeExtractedTextHash() {
        let manifest = (blocks ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { $0.contentHash }
            .joined(separator: "|")
        extractedTextHash = SHA256.hash(data: Data(manifest.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
```

---

## 8. CloudKit translation

CloudKit is currently `cloudKitDatabase: .none` per the data model EDD. The block model is designed to ship correctly when the runtime flag flips. This section documents what happens then.

### 8.1 Record per block

Each `PageBlock` becomes one CKRecord under the page's CKRecord. Heavy payloads (`bodyData`, `drawingData`, `thumbnailData`, `audioData`) promote to CKAsset via `@Attribute(.externalStorage)`.

```
CKRecord: CD_PageBlock
  recordName:           <UUID>
  CD_id:                <UUID>
  CD_sortIndex:         Int
  CD_kindRaw:           "text" | "ink" | "voice"
  CD_heightPoints:      Double
  CD_createdAt:         Date
  CD_modifiedAt:        Date
  CD_plainText:         String?
  CD_ocrText:           String?
  CD_transcript:        String?
  CD_transcriptConfidence: Double
  CD_audioDurationSeconds: Double
  CD_transcriptLanguage: String?
  CD_bodyData:          CKAsset?   (externalStorage)
  CD_drawingData:       CKAsset?   (externalStorage)
  CD_thumbnailData:     CKAsset?   (externalStorage)
  CD_audioData:         CKAsset?   (externalStorage)
  CD_page:              Reference(parent CKRecord)
```

Each record is comfortably under CloudKit's 1 MB limit because heavy data lives in CKAsset. A long note with 50 blocks creates 50 CKRecords + (up to) 200 CKAssets. CloudKit handles this volume cleanly.

### 8.2 Conflict resolution — LWW per block

Two devices editing the same page simultaneously:

| Scenario | Result |
|---|---|
| Both edit block #3 | LWW on block #3's CKRecord. Block #3 takes the latest `modifiedAt`. |
| A edits block #3, B edits block #5 | Both succeed. No conflict. |
| A adds block #6, B adds block #7 | Both succeed; `sortIndex` resolves order. |
| A reorders blocks while B edits one | Reorder lands as `sortIndex` updates; edits land as field updates. Both reconcile. |
| A deletes block #4, B updates block #4 | Delete wins (CloudKit default). B's update is lost; explicit "deleted while editing" notification surfaces in Inbox. |

The block model **localizes conflicts**. Pre-block-model, the single `drawingData` field meant any two-device edit was a full-page conflict. With blocks, the conflict surface is per-block.

LWW per block is the v1 strategy. CRDT is an open question (§23).

> **2026-06-10 caveat.** Per-block LWW localizes conflicts for the *blocks*, but two write patterns in the current `NotebookClient` undermine it: the denormalized `NotePage.extractedText` / `extractedTextHash` aggregates (one field on one record — LWW keeps one device's aggregate, reflecting neither merged state) and gapless `sortIndex` reindexing (one insert dirties every subsequent block's record). Both are release gates for the CloudKit flip — see the **Phase 3 pre-flip checklist** in `data_model_edd.md` §9 for the fixes (local-only derived aggregates; fractional ordering).

### 8.3 Schema deployment checklist (future, when CloudKit is enabled)

Per `CLAUDE.md` "CRITICAL pre-launch action" — applies once CloudKit is promoted:

1. The schema (with `PageBlock`) deployed to **CloudKit Development** before any iCloud testing.
2. Exercise sync with multiple devices over a sample workload.
3. Promote to **CloudKit Production** before App Store submission.
4. Without (3), all users on the App Store build experience silent sync failures.

The block model adds one record type (`CD_PageBlock`) and modifies one (`CD_NotePage`'s relationship list). Both are deployed in the same CloudKit schema promotion when the time comes.

### 8.4 CKAsset lifecycle

`@Attribute(.externalStorage)` auto-promotes Data fields to CKAsset on sync. When a block is deleted, the cascade rule on `NotePage.blocks` deletes the `PageBlock` rows; SwiftData handles the asset garbage collection.

**Asset download is eager, not lazy (corrected 2026-06-10).** An earlier revision of this section claimed assets lazy-fetch when the field is accessed. That is wrong: `NSPersistentCloudKitContainer` (which SwiftData wraps) downloads CKAssets **at sync-import time**. What `.externalStorage` actually provides is lazy faulting *from local disk* — the blob stays out of the row and out of memory until the field is read — not deferred *network* fetch. Consequences: a fresh device signing into a full library downloads every voice memo and ink drawing up front; first-run UX must not assume on-demand asset fetch; and clearing `audioData` post-transcription (which `VoiceSnapshot.audioData: Data?` already supports) is the real lever for keeping sync payloads bounded. The block snapshot path still keeps assets out of *memory* for blocks that aren't being edited — that part is unchanged.

---

## 9. Schema changes

**No migrations.** CloudKit is not yet enabled (`cloudKitDatabase: .none`) and there are no production users. Schema changes are direct edits; local stores that fail to open are reset by reinstalling the app on the dev simulator.

PR 1 lands the full schema change in one commit:

- Add `PageBlock` `@Model`.
- Add `NotePage.blocks` relationship + `extractedText` + `extractedTextHash`.
- Add `NoteRegion.anchorBlockID` + `anchorKindRaw`.
- Add `Notebook.canonicalCanvasWidth` (§6.1).
- Add `PageBlock.contentHash` (§7.5).
- **Delete** `NotePage.drawingData` + `NotePage.ocrText` (now lives per-block on `PageBlock`).

No `VersionedSchema`, no idempotent migration loop, no fallback read paths. If a dev simulator has notebooks authored on the V1 schema, the store fails to open after the change and the user reinstalls.

When CloudKit promotes to Production (or users land), this section gets a follow-up: the data model EDD's `VersionedSchema` framework reactivates, and additive migrations + the CloudKit Production schema deploy become a release gate. See the standing rule in user memory: skip migrations until CloudKit ships.

---

## 10. The drag bar — block height UX

The Apple Notes drag handle is the visible boundary between two adjacent blocks. Dragging adjusts the upper block's `heightPoints`. The block model already has `heightPoints` — the drag bar is its UX.

### 10.1 Component

```swift
struct DragBarView: View {
    let model: Model

    var body: some View {
        Rectangle()
            .fill(model.tintColor)
            .frame(height: model.handleHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.onDragging(value.translation.height)
                    }
                    .onEnded { value in
                        model.onDragEnded(value.translation.height)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(model.accessibilityLabel)
            .accessibilityAction(named: model.increaseActionLabel) { model.onIncrease() }
            .accessibilityAction(named: model.decreaseActionLabel) { model.onDecrease() }
    }

    struct Model {
        let tintColor: Color
        let handleHeight: CGFloat
        let onDragging: (CGFloat) -> Void   // transient — view-local state
        let onDragEnded: (CGFloat) -> Void   // commits via reducer
        let onIncrease: () -> Void
        let onDecrease: () -> Void
        let accessibilityLabel: String
        let increaseActionLabel: String
        let decreaseActionLabel: String
    }
}
```

### 10.2 Reducer actions

```swift
// On NotePageFeature
enum Action {
    case blockHeightDragging(blockID: UUID, transientPoints: CGFloat)  // optional — view holds transient
    case blockHeightChanged(blockID: UUID, newHeightPoints: Double)    // commit
    case blockHeightIncrease(blockID: UUID)                            // accessibility action
    case blockHeightDecrease(blockID: UUID)
    case inkBlockInserted(afterBlockID: UUID?, sortIndex: Int)         // Pencil hits blank text
}

case .blockHeightChanged(let blockID, let h):
    state.blocks[id: blockID]?.heightPoints = max(h, minimumHeight(for: blockID, in: state))
    return .run { _ in try await notebookClient.updateBlockHeight(blockID, h) }

case .blockHeightIncrease(let blockID):
    let cur = state.blocks[id: blockID]?.heightPoints ?? 200
    return .send(.blockHeightChanged(blockID: blockID, newHeightPoints: cur + 20))
```

Mid-drag values live on `@State` in the view (transient — no reducer round trip). Only the commit reaches the reducer.

### 10.3 Constraints

| Rule | Why |
|---|---|
| Ink block `heightPoints` ≥ ink bounding box height | Shrinking below clips strokes. The bounding box is computed from the PKDrawing on every commit. |
| Text block height is **read-only** from the user | Text intrinsically sizes itself. `heightPoints` mirrors the last layout result; the user can't shrink it manually. |
| Empty ink block minimum height = 120pt | Smaller is a dead zone — no room to draw. |
| Voice block height is **content-derived** | Audio waveform + transcript size determine height. Not draggable. |
| Drag bar visible only when `horizontalSizeClass == .regular` AND `notebookType != .textNote` | iPhone / compact: ink is read-only, no need. Pure text notes: no ink blocks. |
| Drag-bar gesture active only when an ink tool is active OR after long-press initiates a drag mode | Prevents accidental height changes while typing. Long-press alternative is needed for Switch Control / Voice Control — see §19. |

### 10.4 Pencil-in-blank-text → new ink block

When the user puts Pencil down in a text block's whitespace:

```
Text block A
  "Meeting notes:"
  [user types Return]
  [blank line]    ← Pencil-down detected on this empty line
  [continued text]
```

The reducer splits the text block at the caret and inserts an ink block between:

```
.inkBlockInserted(afterBlockID: textBlockA.id, sortIndex: textBlockA.sortIndex + 1)
```

Effect:
1. The text after the caret moves to a new text block B (re-indexed at `sortIndex + 2`).
2. A new ink block with default height (200pt) is inserted between A and B.
3. The Pencil stroke begins recording in the new ink block.

This matches Apple Notes' "tap Pencil in a blank area, an ink region appears" behavior. The reducer action is the only seam — `Coordinator` detects the Pencil-in-blank-text condition and emits the action.

---

## 11. Region anchors — ink rect vs text range

The unified `NoteRegion` carries a discriminator. Existing ink anchors are preserved; text anchors are added.

```swift
enum NoteRegionAnchorKind: String, Codable, Sendable {
    case inkRect
    case textRange
}

@Model final class NoteRegion {
    var id: UUID = UUID()
    var page: NotePage? = nil

    /// Which block owns this region's anchor.
    var anchorBlockID: UUID? = nil

    /// Discriminator. Defaults to `.inkRect`.
    var anchorKindRaw: String = NoteRegionAnchorKind.inkRect.rawValue

    // MARK: Ink anchor (kind == .inkRect)
    /// Canonical-canvas coordinates.
    var rectX: Double = 0
    var rectY: Double = 0
    var rectWidth: Double = 0
    var rectHeight: Double = 0

    // MARK: Text anchor (kind == .textRange)
    /// Block tree path identifying the leaf block holding the anchored
    /// span — typically a paragraph or heading ID inside the Text
    /// PageBlock's `RichTextDocument`. Stored as an array of block
    /// IDs (root → leaf) so a nested block (e.g. a list item's
    /// paragraph) is addressable.
    var anchorBlockPath: [UUID]? = nil

    /// Character offset range within the leaf block's joined inline
    /// text. Encoded as UTF-16 code units to align with what the
    /// editor's UITextView reports natively.
    var anchorStartOffset: Int = 0
    var anchorEndOffset: Int = 0

    // Existing association fields — unchanged.
    var headerOCRText: String? = nil
    var linkRecognizedText: String? = nil
    var linkExternalURL: String? = nil
    var linkTargetPageID: UUID? = nil
    var linkTargetNotebookID: UUID? = nil
    var linkTargetPDFID: UUID? = nil
    var eventKitIdentifier: String? = nil

    var isAnchored: Bool = true
}
```

### 11.1 Reading a text-anchored region

```swift
/// Resolve a region's anchored span inside a Text PageBlock's
/// document. Returns `nil` if the path no longer exists (block was
/// deleted) or the offsets exceed the leaf's text length (span
/// deleted).
func range(for region: NoteRegion, in document: RichTextDocument) -> RegionSpan? {
    guard let path = region.anchorBlockPath,
          let leaf = document.block(at: path) else { return nil }
    let text = leaf.joinedInlineText
    guard region.anchorEndOffset <= text.utf16.count else { return nil }
    return RegionSpan(
        path: path,
        startUTF16: region.anchorStartOffset,
        endUTF16: region.anchorEndOffset
    )
}
```

### 11.2 Writing a text-anchored region

```swift
// Selection menu → "Mark Region" path
let regionID = UUID()
let (path, startOffset, endOffset) = state.document.span(for: state.selection)

let region = NoteRegion(
    id: regionID,
    page: page,
    anchorBlockID: textBlockID,
    anchorKindRaw: NoteRegionAnchorKind.textRange.rawValue,
    anchorBlockPath: path,
    anchorStartOffset: startOffset,
    anchorEndOffset: endOffset
)
modelContext.insert(region)
```

The selection's `path` is the chain of block IDs from the document root to the leaf containing the caret. The offsets are UTF-16 code units inside the leaf's joined inline text. Both come from the editor's selection model — see the editor architecture section.

### 11.3 The "regions move with text" guarantee

Anchors track edits because the block path and offsets are kept in sync with the document by the reducer on every mutation:

| User action | Anchor response |
|---|---|
| Type text BEFORE the region span (same leaf) | `anchorStartOffset` and `anchorEndOffset` shift forward by inserted UTF-16 length. |
| Type text WITHIN the region span | `anchorEndOffset` grows by inserted length; `anchorStartOffset` unchanged. |
| Type text AFTER the region span | Offsets unchanged. |
| Delete text within the region span | `anchorEndOffset` shrinks by deleted length. |
| Delete the entire region span | Offsets collapse to equal values. Region's `isAnchored` flips false on next save. |
| Move text into a new block (split paragraph) | Path updates to the new leaf; offsets recomputed relative to the new leaf's text. |
| Delete the entire leaf block | Path no longer resolves. Region's `isAnchored` flips false. |

The reducer's `applyEdit(_:)` step walks every NoteRegion attached to the active block after a mutation and adjusts the offsets / path. Cheap: O(regions × edits_per_save).

**Trailing-edge precision.** Typing at the trailing edge of an anchored span (e.g. cursor is at position `anchorEndOffset`) extends the span only if the user holds the *extend* gesture (selection menu's "extend region"). Default behavior: anchor stays bounded; new characters belong to surrounding text. Matches the "Q3 Budget" stays "Q3 Budget" expectation.

### 11.4 The detach sweeper — text-anchor variant

The existing erasure sweeper on `CanvasFeature` flips `isAnchored = false` when ink inside a region's rect is erased. The text-anchor analog: on every block save, walk every NoteRegion with anchor kind `.textRange`. If its `anchorBlockPath` no longer resolves OR `anchorStartOffset == anchorEndOffset` (span collapsed by deletion), flip to `isAnchored = false`. If the region also carries no other associations, it's deleted outright (existing logic).

### 11.5 Indicator rendering across anchor kinds

`RegionIndicator` is one component. The adapter resolves an anchor-kind-aware Model:

- **Ink rect:** indicator renders at `(rect * scale)` in viewport coordinates, positioned absolutely within the ink block.
- **Text range:** indicator renders inline using the editor's caret-rect API for the start and end of the anchored UTF-16 range. Badges stack to the right of the spanned text or float to a side margin per layout heuristics.

Both surface the same badge row (header / link / event), same ellipsis chip, same tap actions. Different anchor renderers, identical Model API.

---

## 12. Highlights — colors + semantic kinds

Highlights are inline emphasis carried by `Mark.highlight(HighlightKind)` (see §5.3). Default color kinds are visual; the link kind is semantic.

```swift
enum HighlightKind: String, Codable, Hashable, Sendable {
    case yellow
    case red
    case blue
    case green
}
```

**Note on scope.** The original v1 design carried richer highlight kinds (link / event / pdf) on the highlight attribute. Those moved to first-class block-level constructs or `Mark.link(URL)` to keep `HighlightKind` simple. A user "highlights" a span (color-only emphasis); the dispatch pipeline handles semantic associations via `NoteRegion` instead.

### 12.1 Application

```swift
// Selection menu → "Highlight" submenu (Yellow, Red, Blue, Green)
case .highlightApplied(let color):
    state.document.applyMark(.highlight(color), to: state.selection)
    return .send(.persistRequested)
```

### 12.2 Rendering

Inside the Text PageBlock's UITextView, each highlighted inline run carries a translucent background fill at the highlight kind's color, no foreground change. The `BlockDecoratingLayoutManager` does NOT need to draw highlights — the standard `NSAttributedString.Key.backgroundColor` set when flattening the block tree to NSAttributedString is what TextKit 1 renders for the background fill.

### 12.3 Accessibility — color is not the only signal

When "Differentiate Without Color" is on, highlighted runs get a small leading dot character or hairline underline so color-only emphasis remains distinguishable.

### 12.4 Persistence

Highlights persist as `Mark.highlight(_)` cases inside the RichTextDocument's inline runs. No separate model. Removing a highlight is a single inline-marks update; survives all CloudKit sync paths because it's encoded in `bodyData`.

### 12.5 The interaction with NoteRegion

A highlighted span and a `.textRange` NoteRegion can coexist on the same text:

- **Highlight** = inline visual treatment. Lightweight. Lives in the document's inline marks.
- **Region** = anchor for the dispatch pipeline. Carries header text, link target, EventKit ID, multiple associations. Surfaces in the dispatch panel.

A user can highlight "Q3 Budget" yellow AND mark it as a region with a calendar event. The renderer composes both: yellow background from the inline mark + region border + badges from the NoteRegion overlay.

---

## 13. Slash command palette

A shared vocabulary, two presentations. Both wire into the same reducer.

### 13.1 The command vocabulary

```swift
enum SlashCommand: String, Codable, Hashable, CaseIterable, Sendable {
    // Block formatting
    case heading1, heading2, heading3, body, blockQuote, code

    // Lists
    case bulletedList, numberedList, checklist

    // Inserts
    case divider
    case region        // mark current line / selection as a region
    case link          // open link sheet
    case event         // open EventKit picker → embed as highlight or block
    case pdfAttach     // open file picker → embed as PDF region
    case voiceMemo     // record inline voice block
    case image         // future — image attachment

    // Dispatch
    case dispatch      // open the universal Dispatch modal seeded from selection / line
}

struct SlashCommandDescriptor: Sendable, Equatable {
    let id: SlashCommand
    let icon: String           // SF Symbol
    let titleKey: String       // AppStrings key
    let shortcut: KeyboardShortcut?
    let availability: Availability

    enum Availability: Sendable {
        case always
        case requiresSelection  // dispatch, region, link
        case textBlockOnly      // headings, lists
    }
}
```

The descriptor table lives in `SlashCommandRegistry.swift`. Adding a command is one row.

### 13.2 The reducer

```swift
struct SlashCommandPaletteFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var isOpen: Bool = false
        var filterText: String = ""
        var presentation: Presentation = .none
        var selectedID: SlashCommand.ID?  // for keyboard navigation
        var matchedCommands: [SlashCommandDescriptor] = []

        enum Presentation: Equatable, Sendable {
            case none
            case popoverAtCaret(anchor: CGRect)   // Mac, iPad regular
        }
    }

    @CasePathable
    enum Action: Equatable {
        case openRequested(Presentation)
        case filterChanged(String)
        case commandSelected(SlashCommand)
        case dismissed
        case keyboardNavigationKey(KeyDirection)

        enum KeyDirection: Equatable, Sendable { case up, down, enter, escape }
    }

    // ... body
}
```

### 13.3 Presentation per surface

| Surface | Presentation | Trigger |
|---|---|---|
| Mac | `NSPopover` anchored at caret rect | Typing `/` at start of line or word boundary; or `⌘⇧/` shortcut |
| iPad regular + hardware kbd | `UIPopoverPresentationController` from caret rect | Typing `/`; or `⌘⇧/` |
| iPad regular + soft kbd | `UIPopoverPresentationController` from caret rect | Typing `/` (slash is on the primary plane on iPad soft keyboard) |
| iPad compact + hardware kbd | `UIPopoverPresentationController` from caret rect | Typing `/`; or `⌘⇧/` (the hardware keyboard rule overrides the size-class gate — see §3) |
| iPad compact + soft kbd | **No popover.** Accessory bar is the surface. | Slash typed = literal slash inserted. |
| iPhone + hardware kbd (rare) | `UIPopoverPresentationController` from caret rect | Typing `/`; or `⌘⇧/` |
| iPhone + soft kbd | **No popover.** Accessory bar is the surface. | Slash typed = literal slash inserted. |

The reducer doesn't know which presentation it's in — the wiring layer chooses based on `horizontalSizeClass` AND hardware keyboard presence (`GCKeyboard.coalescedKeyboard != nil`). Hardware keyboard wins.

### 13.4 Filtering

When the user types `/he` the matched commands narrow to those whose titleKey contains "he" (heading1, heading2, heading3). Filter uses `localizedStandardContains` against the localized title — so a German user typing `/üb` matches "Überschrift 1".

### 13.5 Keyboard navigation (popover surfaces only)

Arrow keys move `selectedID`. Enter commits. Escape dismisses. Typing more filters; backspace through the slash dismisses.

### 13.6 What commands DO — block-tree mutations

A slash command's `commandSelected` action in the reducer mutates the document. There is no "intent" attribute pass; the block tree's shape IS the formatting.

| Command | Mutation |
|---|---|
| `heading1` / `heading2` / `heading3` | Replace the paragraph block containing the caret with a `.heading(level:)` block carrying the same inline runs. |
| `body` | Replace the block containing the caret with a `.paragraph` block carrying the same inline runs (works to "exit" headings, lists, blockquote, code). |
| `blockQuote` | Wrap the block containing the caret in a `.blockquote(children: [block])`. Successive invocations on the same block re-wrap (rare). |
| `code` | Replace the block containing the caret with a `.codeBlock(text:languageHint:)`, discarding any inline marks (code blocks are plain text). |
| `bulletedList` | If the current block is already a list item, no-op. Otherwise replace the current paragraph with a `.bulletList(items: [.init(content: [paragraph])])`. |
| `numberedList` | Same as bulletedList but `.orderedList`. |
| `checklist` | (deferred) Same shape, custom `ListItem.isChecked: Bool` flag. |
| `divider` | Insert a `.divider` block after the block containing the caret. Caret moves to a fresh paragraph after the divider. |
| `link` / `event` / `pdfAttach` / `voiceMemo` / `image` / `region` / `dispatch` | (each deferred — defers to its own subsystem; see §14 — voice scenarios in §18) |

**Enter on empty list item exits the list.** The reducer's text-input handler watches for `Return` typed while the caret is at the start of an empty `listItem`'s leading paragraph. The handler:

1. Removes that empty `listItem` from the parent `bulletList` / `orderedList`.
2. Inserts a fresh `.paragraph` block after the list, with the caret seeded at offset 0.
3. If removing the empty item drained the list to zero items, the list block is removed too.

Same handler covers `Tab` (nest into a parent listItem's nested list) and `Shift+Tab` (outdent — promote a nested item to its parent's level).

**Slash typed inside a code block is literal.** Code blocks are plain text; the slash menu doesn't open inside them. Same rule as Notion.

---

## 14. Text editing chrome per platform

Same reducer actions across all chromes. Differences are purely in the surface that emits them.

### 14.1 Mac

Surfaces:

| Surface | Commands surfaced |
|---|---|
| Menu bar — `Format` menu | Bold, Italic, Underline, Strikethrough, Heading 1/2/3, Body, Block Quote, Code |
| Menu bar — `Insert` menu | Region, Link, Event, PDF, Voice Memo, Divider |
| Menu bar — `Edit` menu | Find, Find Next, Mark Highlight (with submenu) |
| `NSToolbar` (above content) | Block-type popup, B/I/U toggles, format-painter, voice-memo, dispatch |
| `NSMenu` (right-click) | Custom items: Mark Region, Highlight ▸, Send to Dispatch, plus system Copy/Paste/etc. |
| Floating selection popover | B/I/U, link, highlight, region, dispatch — appears above text selection |
| Slash popover | `/` typed at caret → popover with full command list |
| `UIKeyCommand`s | Cmd+B/I/U, Cmd+Opt+1/2/3, Cmd+K (link), Cmd+/ (slash) |

The reducer is identical to iPad; the AppKit chrome dispatches the same actions.

### 14.2 iPad regular + hardware keyboard

- Software accessory bar **hidden** (UIKit detects `GCKeyboard.coalescedKeyboard != nil`).
- `UIKeyCommand` set identical to Mac: B/I/U, headings, slash.
- Selection menu (`UIEditMenuInteraction`) extended with custom actions (Mark Region, Highlight, Send to Dispatch).
- Slash popover at caret on `/`.
- Pencil gestures (double-tap, squeeze, two-finger hold) continue to dispatch toolbar actions.

### 14.3 iPad regular + soft keyboard

- **Accessory bar visible** above keyboard. Single row, mode-switching. More horizontal room than iPhone — extra buttons visible without scrolling.
- Slash popover also available — typing `/` opens the popover above the keyboard.
- Selection menu extended.
- Aa popover for block/inline formatting.
- Drag bar for ink block heights remains active.

### 14.4 iPad compact (Slide Over) / iPhone

This is the constrained surface.

#### 14.4.1 The accessory bar — single-row mode switching

```
DEFAULT MODE  (caret active, no selection)
[ Aa ][ B I U ][ ≡ ][ ☐ ][ ─ ][ ⊕ ][ 🎙 ][ ⇨ ][ ↩ ][ ⌄ ]
  format inline list check divider insert voice dispatch undo dismiss
  ↑ scrolls horizontally if a future addition pushes content off-screen

SELECTION MODE  (text selected; auto-engaged on selection)
[ B I U S ][ Aa ][ ◐ ][ ◇ ][ ⇨ ][ ← ]
  inline   format hi-lite region dispatch back

HIGHLIGHT MODE  (Highlight chosen from selection mode)
[ ● ][ ● ][ ● ][ ● ][ 🔗 ][ 📅 ][ 📄 ][ ← ]
  yellow red  blue green link event pdf back

INSERT MODE  (⊕ chosen from default)
[ ◇ Region ][ 🔗 Link ][ 📅 Event ][ 📄 PDF ][ ─ Divider ][ 🎙 Voice ][ ← ]
  each opens a dedicated sheet for multi-step entry
```

#### 14.4.2 The Aa popover (the one popover concession)

Block / inline formatting density makes a single-row representation impractical. Tapping `Aa` opens a popover ABOVE the bar with three sections: block type list, inline toggles, list styles. Tap commits and dismisses.

```
┌──────────────────────────────┐
│ Title                         │
│ Heading                       │
│ Subheading                    │
│ Body  ✓                       │
│ Code                          │
│ Block Quote                   │
├──────────────────────────────┤
│   B    I    U    S            │
├──────────────────────────────┤
│ • Bulleted                    │
│ 1. Numbered                   │
│ ☐ Checklist                   │
└──────────────────────────────┘
```

Multi-row, scrollable, dismissible by tap-outside. This is the same UX Apple Notes uses; we're matching, not innovating, on this surface.

#### 14.4.3 Multi-step inserts → full sheets

Region-from-selection: opens the dispatch flow (existing modal). Link: opens link input sheet (existing). Event: opens an EventKit picker sheet. PDF: opens a file picker. Voice: opens the voice capture screen (§18). The bar returns to default mode after the sheet commits.

#### 14.4.4 The `/` character

**Never intercepted on iPhone or iPad compact.** Inserts as a literal slash. The accessory bar is the only command surface. This is a non-issue for the user because: (a) the bar is right there; (b) Apple Notes has trained the user that `/` doesn't mean anything in a note.

#### 14.4.5 Discoverability

The default mode bar shows the most common commands prominently. The `⊕` insert mode educates the user about what else is available. We do NOT show a "try typing /" hint on iPhone — there's nothing for `/` to do on iPhone. The hint exists on Mac and iPad regular as part of the empty-state placeholder ("Start typing, or `/` for commands").

---

## 15. Pencil ↔ keyboard handoff on iPad

iPad regular is the only platform where ink and text authoring coexist. The handoff must be implicit — the user never selects "I'm typing now" vs "I'm drawing now."

### 15.1 The implicit rule

| Input | Effect |
|---|---|
| Finger or Pencil tap on a text block | Caret moves; keyboard appears if not present; accessory bar visible if no hardware keyboard. |
| Pencil tap on an ink block | Ink tool engages on that block; keyboard dismisses. |
| Pencil tap on a blank line in a text block | New ink block inserted; Pencil stroke begins. (§10.4) |
| Pencil double-tap | Toggles eraser (existing). |
| Pencil two-finger hold | Pushes `.region` tool (existing). |
| Hardware keyboard typed | Caret in active text block; keyboard input flows; accessory bar hidden (already gone). |
| Finger drag on drag bar | Adjusts ink block height. |

### 15.2 The state machine

`NotePageFeature.State.activeInput`:

```swift
enum ActiveInput: Equatable, Sendable {
    case none
    case text(blockID: UUID, caret: AttributedString.Index?)
    case ink(blockID: UUID, tool: ToolID)
}
```

Transitions are driven by the actions above. The reducer enforces invariants:
- Two `ActiveInput`s cannot coexist.
- A Pencil tool change while `activeInput == .text` deactivates text; vice versa.

### 15.3 Concurrent finger + Pencil

iPadOS 26 supports concurrent Pencil + finger gestures naturally — palm rejection handles the rest. The reducer treats them as separate event streams; the latest event-type-changed action sets `activeInput`.

### 15.4 The Coordinator boundary

Per CLAUDE.md "Canvas + TCA boundary": 60fps stroke recording stays imperative inside `PKCanvasViewDelegate`. Only stroke-completion and gesture-recognition events round-trip through the reducer. Same rule applies: text input via `UITextViewDelegate` keeps every keystroke local; only block-level commits (newline, paste, formatted insert) reach the reducer.

---

## 16. Selection menu extensions

`UIEditMenuInteraction` on iOS and `NSMenu` on macOS get our custom items appended to the system Copy/Cut/Paste set.

### 16.1 iOS / iPadOS

```swift
extension TextBlockHostingController: UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let custom = UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: AppStrings.TextEditing.markRegion,
                     image: UIImage(systemName: "rectangle.dashed")) { [weak self] _ in
                self?.store.send(.markRegionRequested)
            },
            UIMenu(title: AppStrings.TextEditing.highlight,
                   image: UIImage(systemName: "highlighter"),
                   children: highlightSubmenuItems()),
            UIAction(title: AppStrings.TextEditing.sendToDispatch,
                     image: UIImage(systemName: "paperplane")) { [weak self] _ in
                self?.store.send(.dispatchFromSelectionRequested)
            },
        ])
        return UIMenu(children: suggestedActions + [custom])
    }
}
```

### 16.2 macOS

`NSMenu` extension via `validateMenuItem(_:)` and the responder chain. Same actions, native AppKit menu.

### 16.3 Accessibility

System Copy/Cut/Paste are accessibility-first; custom items inherit that contract because they're standard `UIAction` / `NSMenuItem`. Voice Control "Tap Mark Region" works without additional wiring.

---

## 17. Keyboard shortcut inventory

The full set, identical across hardware-keyboard platforms (Mac, iPad+kbd, iPhone+kbd):

| Shortcut | Action |
|---|---|
| ⌘B | Toggle bold |
| ⌘I | Toggle italic |
| ⌘U | Toggle underline |
| ⌘⇧X | Toggle strikethrough |
| ⌘⌥1 / ⌘⌥2 / ⌘⌥3 | Heading 1 / 2 / 3 |
| ⌘⌥0 | Body |
| ⌘⌥> | Block quote |
| ⌘⌥C | Code |
| ⌘⇧7 | Numbered list |
| ⌘⇧8 | Bulleted list |
| ⌘⇧9 | Checklist |
| ⌘K | Insert link |
| ⌘⇧/ | Open slash menu (⌘/ is reserved by the system for "Show All Help" on Mac and not overridable in practice) |
| ⌘⇧H | Toggle highlight (last color) |
| ⌘⇧R | Mark region from selection |
| ⌘⇧D | Send to Dispatch |
| ⌘⇧V | Insert voice memo |
| ⌘Z / ⌘⇧Z | Undo / Redo |
| ⌘F | Find in note |
| ⌘G / ⌘⇧G | Find next / previous |

All shortcuts dispatch reducer actions through `UIKeyCommand` (iOS/iPadOS) and `NSResponder` / first-responder chain (Mac). No platform branching in the reducer.

### 17.5 Undo design — page-scoped, cascade rule

Undo is **page-scoped** (Apple Notes' model). `⌘Z` undoes the most recent change anywhere on the current page; cross-page undo is not supported (page swipe commits the prior page's edits as a stable point).

The implementation cascades across three undo managers, in priority order:

| Layer | Owned by | Undoes |
|---|---|---|
| Active text block | `UITextView.undoManager` (TextKit native) | Text inserts/deletes, format toggles, list operations within the active block |
| Active ink block | `PKCanvasView.undoManager` (PencilKit native) | Stroke add/remove/erase within the active block |
| Page-level | `NotePageFeature` logical undo stack | Block insert/delete/reorder, drag-bar height changes, region anchor changes, highlight applies |

> **Dependency (2026-06-10).** The native-undo layer only works if document↔editor sync never wholesale-replaces `textView.attributedText` during normal editing — replacement destroys the native stack. This is one of the load-bearing reasons for the imperative text boundary (§22.4.1): commands apply as incremental text-storage edits, which register undo natively.

**Cascade rule on `⌘Z`:**

1. Ask the active block's native undo manager first. If `canUndo`, send it `undo()` and stop.
2. Otherwise ask the page-level reducer-managed stack. If non-empty, pop one entry and apply its inverse.
3. If both are empty: no-op (visual flash on the page chrome if Reduce Motion is off; silent otherwise).

`⌘⇧Z` (Redo) cascades the same way: native first, then page-level.

**Page-level undo entries** are reducer actions plus their inverse:

```swift
enum PageUndoEntry: Equatable, Sendable {
    case blockInserted(blockID: UUID, at: Int)
    case blockDeleted(blockID: UUID, snapshot: PageBlockSnapshot, at: Int)
    case blocksReordered(previousOrder: [UUID])
    case blockHeightChanged(blockID: UUID, previousHeight: Double)
    case regionAnchorChanged(regionID: UUID, previousAnchor: NoteRegionAnchor)
    case highlightApplied(blockID: UUID, range: NSRange, previousAttribute: HighlightAttribute.Value?)
}
```

`NotePageFeature.State.undoStack: [PageUndoEntry]` and `redoStack: [PageUndoEntry]` carry the page-level history. Standard "push on action commit, clear redo on new action" semantics. Cap at 100 entries per page; older entries fall off the bottom.

**Boundary discipline.** The reducer does NOT push entries for native block actions — those live entirely in the native undo manager. A page-level entry is pushed only when the reducer mutates state directly (block insert, reorder, etc.). Without this rule, undo would double-fire (native undoes the text edit, then the reducer undoes its tracked "text changed" entry).

**Cross-block subtlety.** Activating a different block doesn't drain the previous block's native undo manager — it lives with the block. If the user types in block A, switches to block B, types there, switches back to A, and hits `⌘Z`, the cascade asks block A's native manager (still holding A's edits) and undoes there. This matches user expectation.

**Persistence.** Undo stacks are session-only. Page swipe / app background drains the page-level stack (the native managers persist as long as their `PKCanvasView`/`UITextView` instances do, which they don't across page swipes). This is consistent with Apple Notes: navigating away ends the undo session for that note.

---

## 18. Voice-to-text architecture

Voice spans three distinct flows. Each maps to a separate UI affordance and reducer action; the underlying `SpeechService` (§18.1) and `PageBlockKind.voice` payload (§5) compose all three.

### 18.0 The three voice flows

**Scenario A — Dictation INTO a block.** The user is typing inside a Text PageBlock, taps a mic affordance (slash command `/dictate`, accessory bar mic icon, or keyboard shortcut), and speaks. `SpeechService` streams partial transcripts; the reducer inserts the recognized text as inline runs into the **currently-focused block** — same path as keyboard input. No new block is created. No audio is stored. Schema impact: none — pure UI flow.

**Scenario B — Voice recording block.** The user invokes `/voiceMemo` (or the accessory bar voice icon) and records audio. A new **Voice PageBlock** is created on the page; recording captures into `PageBlock.audioData`. The block's view (`VoiceBlockView`) is a peer of `TextBlockView` / `InkBlockView` with playback controls: play/pause, scrubber, duration, waveform. No transcript needed at capture time — the user can request transcription later via the block's menu. Schema: existing `PageBlockKind.voice` already covers this.

**Scenario C — Voice → transcript → text block.** Composes A + B. Starting from an existing voice block (or recording one fresh), the user taps "Transcribe" in the block's menu. `SpeechService.transcribeFile(url:locale:)` produces a transcript. The reducer:

1. Creates a new **Text PageBlock** below the voice block.
2. Seeds its `RichTextDocument` with one or more `.paragraph` blocks containing the transcript.
3. Writes the source voice block's UUID into `PageBlock.sourceVoiceBlockID` on the new text block so a "play original" affordance can appear next to the transcribed text.
4. Leaves the voice block in place (user can delete manually if they don't want to keep the audio).

Schema impact: add `sourceVoiceBlockID: UUID?` to PageBlock. One optional UUID column.

**Order of implementation:** Scenario B ships first (it's the foundation — `PageBlockKind.voice` + a player view). Scenario A follows once `SpeechService` exists. Scenario C composes from A + B and lands last.

---

Voice is a first-class capture surface, not just system dictation. System dictation continues to work in any text block via the keyboard's microphone key — that path requires no special handling. The sections below cover the **voice memo block** and the **voice-first capture surface** that underpin scenarios B and C.

### 18.1 `SpeechService` dependency

```swift
struct SpeechService: Sendable {
    var requestAuthorization: @Sendable () async -> SpeechAuthorization
    var isAvailable: @Sendable () -> Bool
    var supportedLocales: @Sendable () -> Set<Locale>

    /// Begin live capture. Returns an AsyncStream of capture events
    /// (partial transcripts, audio levels). The caller awaits the
    /// stream to render live UI, then calls `stopCapture` to finalize.
    var startCapture: @Sendable (Locale) async throws -> AsyncStream<CaptureEvent>

    /// Stop the active capture. Returns the audio URL + final transcript.
    var stopCapture: @Sendable () async throws -> CaptureResult

    /// Cancel an in-flight capture without producing a result.
    var cancelCapture: @Sendable () async -> Void

    /// Offline transcription of an existing audio file (e.g., user
    /// imported a memo or recaptured transcript for a corrected language).
    var transcribeFile: @Sendable (URL, Locale) async throws -> CaptureResult
}

enum SpeechAuthorization: Equatable, Sendable {
    case notDetermined, denied, restricted, authorized
}

enum CaptureEvent: Sendable {
    case partialTranscript(String, confidence: Double)
    case audioLevel(Float)
    case error(SpeechError)
}

struct CaptureResult: Equatable, Sendable {
    let audioURL: URL
    let transcript: String
    let confidence: Double
    let durationSeconds: Double
    let language: String  // BCP-47
}
```

The live value wraps **`SpeechAnalyzer` with a `SpeechTranscriber` module** (iOS 26's modern on-device path — long-form quality, ~2× faster than equivalent Whisper-class models). `SFSpeechRecognizer` becomes the fallback only for locales `SpeechTranscriber` doesn't yet support; the `SpeechService` dependency abstracts both behind a single interface so callers don't branch. Audio file is written to the application-support directory at capture time; on commit, it moves into the synced model container and CKAsset-promotes.

### 18.2 Voice block UI

```
┌──────────────────────────────────────────────────────┐
│ ▶  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  0:32   │
│ ─────────────────────────────────────────────────── │
│ We need to confirm the Q3 budget by Friday. Loop in │
│ Sarah and CC legal. Action item: send draft today.  │
│                                            ✎ edit   │
└──────────────────────────────────────────────────────┘
```

- Top row: play/pause, waveform stub, duration. Tap-to-scrub.
- Below: transcript, rendered as editable text. Tapping the pencil enters edit mode (live editing on iPhone; inline on iPad/Mac).
- Audio is the **source of truth**; transcript is a **derived field the user can correct**. Edits to the transcript persist; they don't re-run recognition.
- Low-confidence words rendered with a subtle dotted underline (the `.transcriptConfidence` field carries a per-word breakdown when available). Tap the word to hear that segment.

### 18.3 Voice-first capture surface

A deliberate, discoverable home-screen entry point — not buried in a slash menu, not gated behind opening a note. This is the inclusion-as-polish move:

- **Home screen** has a prominent microphone button (the same SF Symbol pattern as the "+" for new note).
- Tapping → full-screen capture UI: large pulsing mic icon, live transcript, "Done" / "Cancel". No other chrome.
- On "Done": creates a new note in the user's default destination notebook (configurable in Settings), containing a single voice block. Navigates to the new note.
- A Siri shortcut "Start a From Ink voice note" invokes the same flow hands-free. Result is the same new note.
- ActivityKit Live Activity (lock screen / Dynamic Island) shows the recording state — user can pause/resume/finish without unlocking. (Stretch goal; can ship in a follow-up.)

The capture screen reuses the same `VoiceCaptureFeature` reducer as inline-in-note recording. The differences are visual chrome and the destination of the resulting voice block.

### 18.4 `VoiceCaptureFeature` reducer

```swift
struct VoiceCaptureFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var liveTranscript: String = ""
        var audioLevel: Float = 0
        var elapsedSeconds: Double = 0
        var authorization: SpeechAuthorization = .notDetermined
        var error: SpeechError? = nil

        enum Phase: Equatable, Sendable {
            case idle
            case requestingPermission
            case recording
            case finalizing
            case complete(CaptureResult)
            case cancelled
        }
    }

    @CasePathable
    enum Action: Equatable {
        case startRequested
        case authorizationResolved(SpeechAuthorization)
        case captureEvent(CaptureEvent)
        case stopRequested
        case cancelRequested
        case captureCompleted(CaptureResult)
        case errorOccurred(SpeechError)
    }

    @Dependency(\.speechService) var speech
    @Dependency(\.calendarContext) var cal

    var body: some Reducer<State, Action> { /* ... */ }
}
```

### 18.5 Permissions

Two permission grants required:

| Permission | InfoPlist key | Required for |
|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` | Recording audio |
| Speech recognition | `NSSpeechRecognitionUsageDescription` | Live + offline transcription |

The first time the user invokes voice capture, both are requested in sequence via `PermissionsFeature`. Denial of speech-recognition still allows audio-only capture (recording is preserved; transcript is empty). Denial of microphone disables the feature entirely with a clear in-app explanation and a deep link to Settings.

### 18.6 Storage & CloudKit

`audioData` lives on `PageBlock` per §5.1, externalStorage → CKAsset. The captured m4a is typically 100-500 KB per minute; a 5-minute memo is ~2 MB — comfortably handled by CloudKit. Transcript text is in the `transcript` field.

Voice blocks count toward the page's `extractedText` for search:

```
page.extractedText = (
    text blocks' plainText ∪
    ink blocks' ocrText ∪
    voice blocks' transcript
).joined(by: sortIndex)
```

### 18.7 Read-aloud composition (deferred, but the data is ready)

For a future "Read this entire note aloud" action, the renderer walks blocks in sort order and:
- Text block → AVSpeechSynthesizer reads `plainText`.
- Ink block → reads `ocrText`. If empty, says "Drawing block, no recognized text."
- Voice block → plays `audioData` directly (preserves the original speaker's voice).

The accessibility section (§19.9) covers this in more detail.

---

## 19. Accessibility & inclusive design

This is not a separate workstream. It is the criterion against which every component is evaluated. The architecture choices we've made — reducer actions as command vocabulary, block-ordered document model, resolved-Model views — give us most of accessibility for free. This section makes the remaining work explicit.

### 19.1 Scope

We are building for all four Apple accessibility categories simultaneously:

| Category | Tooling we support |
|---|---|
| Vision | VoiceOver, Dynamic Type, Increase Contrast, Bold Text, Reduce Transparency, Smart Invert, Differentiate Without Color |
| Motor | Switch Control, Voice Control, AssistiveTouch, pointer/trackpad, Full Keyboard Access |
| Hearing | Live captions for voice blocks, visual cues for audio events, no audio-only feedback |
| Cognitive | Reduce Motion, predictable layout, clear language, no time-pressure interactions |

### 19.2 VoiceOver structure per block

Reading order is block sort-index, top to bottom. Each block kind has a consistent VoiceOver shape:

| Block | Element shape | Label format |
|---|---|---|
| Text | Inherits AttributedString accessibility traits. Headings announce as headings (`UIAccessibilityTrait.header`). Highlights announce via run-attribute callouts. Region anchors announce as "Region: [header text]" prefixes. | The rendered text |
| Ink | Single element, label = ocrText, hint = "Drawing block, [height] points tall" | "Drawing block: 'Q3 budget meeting notes'" |
| Voice | Container with three subelements: play button, scrubber, transcript | "Voice memo, 32 seconds. Transcript: '[transcript]'. Tap to play." |
| Region indicator | Single element with custom actions for tap-to-open and ellipsis | "Region: 'Q3 Budget'. Two attachments: link to Linear, calendar event Friday. Actions available." |
| Drag bar | Single element with two custom actions | "Block height handle. Actions: Increase height, Decrease height." |

### 19.3 Custom rotors

VoiceOver's rotor lets the user navigate by semantic category. We register four:

| Rotor | Iterates |
|---|---|
| Regions | All `NoteRegion`s on the current page, in sort-index order |
| Headings | All H1/H2/H3 in text blocks PLUS regions with header text |
| Voice memos | All voice blocks on the current page |
| Attachments | All link / event / PDF associations across regions |

Implementation: `UIAccessibilityCustomRotor` on the page wiring view. Each rotor's `itemSearchBlock` walks the block snapshot in the appropriate order.

### 19.4 Dynamic Type & body scaling

- All chrome (toolbar, accessory bar, slash menu, sheets) uses `Font.preferredFont(.body)` / equivalent scaling tokens.
- Text block body uses Dynamic Type for the user-set content size. The block re-layouts on `UIContentSizeCategory.didChangeNotification`.
- Ink block content does NOT scale with Dynamic Type. Strokes are not text; they are visual content. They scale only with viewport (§6).
- Voice block transcript uses Dynamic Type.
- Region indicator badges scale with `.accessibility1` size at minimum, capped at `.accessibility3` so a 44pt-minimum tap target remains visually proportional.

When the user enables an accessibility size (`.accessibilityMedium` and up):
- Text blocks grow substantially → block stack relayouts → ink blocks stay at canonical-scale height but their screen position shifts.
- The accessory bar grows in height to maintain 44pt-minimum hit targets at the larger size.
- The slash popover grows.

### 19.5 Color contrast

- All highlight colors are tested against canvas color in light and dark mode to WCAG AA (4.5:1 for normal text, 3:1 for large).
- When `UIAccessibility.isDarkerSystemColorsEnabled` (Increase Contrast) is true, highlight colors switch to a high-contrast variant (saturated, more opaque background).
- When `UIAccessibility.shouldDifferentiateWithoutColor` is true, highlights and region indicators render with an additional icon overlay so kind is conveyed without depending on hue.
- `accessibilityIgnoresInvertColors` is set on ink rendering and voice waveforms — Smart Invert should not invert handwriting or visualizations.

### 19.6 Custom gesture alternatives

Every custom gesture has a non-gesture alternative. The EDD's hard rule: if a feature requires a custom gesture to invoke, it does not exist on iPhone/Mac, and on iPad it has a tap path.

| Gesture | Required alternative |
|---|---|
| Pencil two-finger hold → push `.region` tool | Lasso tool → completes a region → action menu (existing). Long-press with single finger also triggers the same code path on iPad. |
| Pencil double-tap → toggle eraser | Tap eraser tool in toolbar (existing). |
| Drag bar continuous drag | Accessibility action "Increase block height" / "Decrease block height" with 20pt steps. |
| Highlight via selection | Selection menu → Highlight submenu (the same path keyboard users use). |
| Slash menu via typing | `⌘⇧/` keyboard shortcut. On iPhone, the accessory bar serves the same role. |

### 19.7 Switch Control & Voice Control

Switch Control:
- All interactive elements have `isAccessibilityElement = true` with semantic labels.
- The accessory bar's mode-switching presents a fixed scan order per mode.
- The slash popover's list is keyboard-arrow-navigable, which Switch Control inherits.
- The drag bar's two custom actions appear in the scanner's action menu.

Voice Control:
- The reducer action vocabulary maps to spoken commands via the components' `accessibilityLabel` text. "Tap Heading 1", "Tap Insert", "Tap Mark Region" all work without explicit Voice Control hints.
- Slash command titles in `AppStrings` are written to be voice-tappable — short, distinct, no overloaded words.
- For commands that are difficult to speak ("⊕" insert), the accessibility label is the localized name ("Insert"), not the symbol.

Full Keyboard Access:
- The `Tab` cycle on iPad+kbd / Mac visits every interactive element in reading order.
- The accessory bar is reachable via keyboard when soft keyboard is active.

### 19.8 Reduce Motion

Per `feedback_reduce_motion.md`: custom transitions honor `accessibilityReduceMotion` and fall back to `.opacity`. Applied to:
- Slash popover open/close (default: scale + fade; reduced: fade only)
- Accessory bar mode switch (default: cross-dissolve + slide; reduced: cross-dissolve)
- Drag bar resize commit (default: spring snap; reduced: linear 80ms)
- Voice capture mic pulse (default: continuous pulse; reduced: static)
- Live transcript word-by-word appearance (default: subtle fade-in per word; reduced: append immediately)

### 19.9 Read-aloud action

A first-class "Read this note" action on every page header, surfaced to:
- VoiceOver users automatically (it's a regular accessibility action).
- Sighted users via the page menu (so the feature is discoverable, not VoiceOver-only).

Behavior:
- Walks blocks in sort order.
- Text → `AVSpeechSynthesizer` reads `plainText` with the user's preferred voice and rate.
- Ink → reads `ocrText`. If empty: "Drawing block, no recognized text."
- Voice → plays `audioData` (original speaker's voice, not synthesized).
- Highlights announce as "Highlight begin... yellow... [text]... end."
- Regions announce as "Region begin... [header text]... [text]... end."

### 19.10 The accessibility audit checklist

For every Component view added to the codebase, the PR template (we'll update it) includes:

```
[ ] accessibilityLabel set on every interactive element
[ ] accessibilityHint set when behavior is non-obvious
[ ] accessibilityTraits accurate (button, header, link, ...)
[ ] Custom actions registered for any custom gestures
[ ] Tested under Dynamic Type at .accessibilityExtraExtraLarge3
[ ] Tested under VoiceOver — reading order, label clarity
[ ] Tested under Increase Contrast
[ ] Tested under Reduce Motion
[ ] Tested under Differentiate Without Color (if color-coded)
```

This is the operational discipline that turns "we care about accessibility" into "this PR meets accessibility."

---

## 20. Localization

Per the localization EDD, all UI text routes through `AppStrings`. The text editor adds new namespaces:

```
AppStrings+TextEditing.swift
  - block type labels (Title, Heading, Body, Block Quote, Code)
  - inline format labels (Bold, Italic, Underline, Strikethrough)
  - list labels (Bulleted, Numbered, Checklist)
  - command labels (Mark Region, Highlight, Insert Link, Send to Dispatch, ...)
  - accessory bar mode names (Default, Selection, Highlight, Insert)
  - accessibility action names (Increase height, Decrease height)

AppStrings+SlashCommand.swift
  - one entry per SlashCommand case
  - short titles (voice-tappable, fits accessory mode rows)

AppStrings+VoiceCapture.swift
  - prompts, permission explanations, error messages

AppStrings+Accessibility.swift
  - VoiceOver labels for region indicators, drag bars, block kinds
  - "Drawing block: %@", "Voice memo, %@ seconds", "Region: %@"
```

### 20.1 RTL layout

- Text blocks inherit `AttributedString`'s natural direction handling. RTL languages (Arabic, Hebrew) render correctly without intervention.
- Accessory bar mode-switch arrows: use direction-aware SF Symbols (`arrow.backward`, not `arrow.left`) per `feedback_directional_sf_symbols.md`.
- Slash menu popover anchors to the caret on the leading edge — automatically correct for RTL.
- Ink blocks have no concept of direction; canvas is direction-agnostic.

### 20.2 Foundation Models input

Per `CLAUDE.md`: "Foundation Models output is not localized." The aggregated `extractedText` fed to FM is whatever language the user wrote in — FM handles it. The chrome around the FM output is localized.

### 20.3 Voice capture locale

`SpeechService.startCapture(_:)` takes a Locale. The capture screen offers a language picker (defaulting to `Locale.current`); the chosen locale is locked to the resulting voice block via `transcriptLanguage`. Re-transcription in a different language is a deliberate user action, not automatic.

---

## 21. Testing strategy

Per the view layer EDD and `CLAUDE.md`.

### 21.1 Reducer tests — `FromInkTests/Features/Text/`

Every reducer action produces a verified state transition via `TestStore`. Dependencies are mocked deterministically:

```swift
final class TextEditingFeatureTests: XCTestCase {
    func test_formatToggled_appliesBold() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(
                activeBlockBody: AttributedString("Hello world"),
                selection: range(of: "Hello")
            ),
            reducer: { TextEditingFeature() }
        )

        await store.send(.formatToggled(.bold)) {
            $0.activeBlockBody = expectedBoldAttributedString
        }
    }

    func test_markRegionFromSelection_createsRegionWithTextAnchor() async {
        let store = TestStore(
            initialState: TextEditingFeature.State(/* ... */),
            reducer: { TextEditingFeature() },
            withDependencies: {
                $0.notebookClient = NotebookClient(/* test fixtures */)
                $0.uuid = .incrementing
            }
        )

        await store.send(.markRegionRequested) {
            // assert the region was added to state with .textRange anchor
        }
    }
}

final class SlashCommandPaletteFeatureTests: XCTestCase {
    func test_filterChanged_narrowsCommands() async { /* ... */ }
    func test_commandSelected_dispatchesAndDismisses() async { /* ... */ }
}

final class VoiceCaptureFeatureTests: XCTestCase {
    func test_startRequested_requestsPermission_thenBeginsRecording() async { /* ... */ }
    func test_captureCompleted_emitsResult() async { /* ... */ }
}
```

### 21.2 Snapshot tests — `FromInkSnapshotTests/`

Stateless component views only (no Store). Each accessory bar mode, slash popover, voice block, region indicator, drag bar gets a snapshot. Critical breakpoints:

```
TextAccessoryBarView - default mode - iPhone SE (compact width)
TextAccessoryBarView - selection mode - iPhone 15 Pro Max
TextAccessoryBarView - insert mode - iPad portrait (Slide Over)
TextAccessoryBarView - default mode - .accessibilityExtraExtraLarge3
TextAccessoryBarView - default mode - RTL (Arabic)

SlashMenuPopoverView - all commands - light mode
SlashMenuPopoverView - filtered - dark mode + Increase Contrast

VoiceBlockView - playing - light - body size
VoiceBlockView - playing - dark - .accessibilityExtraLarge

RegionIndicator - ink anchor with 2 badges - light
RegionIndicator - text anchor inline - light - Dynamic Type body
RegionIndicator - text anchor inline - Differentiate Without Color

DragBarView - hover state - iPad regular
DragBarView - resting - iPhone (verifies invisible when ink not authorable)
```

### 21.3 Accessibility audit (CI)

A test that asserts every Component view in the feature has non-empty accessibility labels on interactive elements. Implemented via reflection over the view tree under XCUI. Runs in CI on every PR.

### 21.4 Speech service mocks

`SpeechService.testValue` returns deterministic transcripts and audio URLs (test bundle fixtures). No real microphone access in tests. Live capture is mocked as an immediate AsyncStream of pre-canned events.

### 21.5 Real-OCR fixtures (no mocking)

Per `CLAUDE.md`: "Do not mock `VNRecognizeTextRequest` — use real fixtures of known handwriting images." Same rule continues. Block-level OCR runs against shipped sample handwriting PNGs in the test bundle.

---

## 22. Refactor plan

The block model and hybrid editor touch substantial existing code. The refactor sequence below ships incrementally — no build flag (no migrations means no staged rollout to gate; per the user memory rule, schema lands directly).

> **2026-06-09 revision.** Phases 1, 2, 3 are substantially shipped — `PageBlock` schema, `NotebookClient` block CRUD, `TextEditingFeature` reducer, `TextBlockView`, `SlashCommandPaletteFeature` with vocabulary + filter, notebook type picker. The text-experience branch has 11 commits already on `alex-blair/text-experience`.
>
> The block-tree pivot supersedes the parts of Phase 2/3 that built on `AttributedString` + `PresentationIntent`. Phase 2.5 below is the migration path.

### 22.1 Phase 1 — schema (no UI change) — **SHIPPED**

PageBlock @Model, NotePage.blocks, NoteRegion anchor discriminator, Notebook.canonicalCanvasWidth, PageBlock.contentHash, NotebookClient CRUD all on the branch.

### 22.2 Phase 2 — text block editor (AttributedString version) — **SUPERSEDED, partially shipped**

The first pass of `TextEditingFeature` + `TextBlockView` shipped on top of `AttributedString` + `PresentationIntent`. Manual testing exposed that `PresentationIntent` does not paint visually under TextEditor or TextKit 2 — see §5.3. The reducer's contracts (selection-aware block formatting, slash trigger, debounced persist, palette wiring) all survive; the content shape and the editor view change.

### 22.3 Phase 3 — slash command palette — **PARTIALLY SHIPPED**

Vocabulary, registry, popover, filter, keyboard-nav state, selection-aware actions all on the branch. The palette's UI ships unchanged; what each command DOES changes to mutate the block tree (§13.6). Keyboard shortcuts and selection-menu integrations not yet shipped.

### 22.4 Phase 2.5 — block tree refactor (NEW, supersedes the AttributedString approach)

The pivot. Each commit isolates one concern so review can confirm one thing at a time. All on `alex-blair/text-experience`.

1. **`RichTextDocument` value types** — define `Block`, `ListItem`, `Inline`, `Mark`, `HighlightKind` in `FromInk/FromInk/RichTextDocument.swift`. Hand-written Codable conformance for `indirect enum Block`. Lenient decoder for forward-compatibility. Round-trip tests, including unknown future cases.
2. **`PageBlockSnapshot` refactor** — replace `body: AttributedString?` with `document: RichTextDocument?`. Update `PageBlockSnapshot.encodeBody` / `decodeBody` helpers to JSON-encode the document. Tests pin the new round-trip and confirm the schema version field travels through.
3. **`TextEditingFeature` rewrite** — replace `editingBody: AttributedString` with `document: RichTextDocument`. Selection model: `BlockTreeSelection` (block path + UTF-16 offset range inside the leaf). Slash commands and inline formatting actions mutate the document. Reducer tests are largely rewritten — old AttributedString tests retire.
4. **`TextKitEditorView` rewrite** — delete the broken TextKit 2 version. New view hand-builds the TextKit 1 stack with a `BlockDecoratingLayoutManager` subclass. Flattens the document to NSAttributedString (paragraph per leaf block, `blockType` tag attribute per paragraph). Parses keystroke edits back into document mutations. Manages `typingAttributes` after every block-format change.
5. **`BlockDecoratingLayoutManager`** — extended from the PoC. Draws blockquote bar + tint, code block tint + indent, list bullets / numbers (via custom drawBackground rather than NSTextList, since UITextView's NSTextList honoring is unreliable), divider hairline. Heading typography lives in paragraph attributes, no custom drawing needed.
6. **`TextBlockView` swap** — switch to the new editor. Model surface stays the same so the wiring view and adapter don't move.
7. **NoteRegion text-range anchor migration** — drop `RegionAnchorAttribute` and the corresponding `AttributeScopes.FromInkAttributes`. Update `NoteRegion` schema with `anchorBlockPath`, `anchorStartOffset`, `anchorEndOffset`. Reducer step keeps anchors in sync on every document mutation.
8. **Delete the PoC** — `SlashEditorPoC.swift` and the temporary home-screen button overlay. Reducer is the truth now.

### 22.4.1 Addendum — the imperative text boundary (2026-06-10)

Commits 4–8 shipped with a **bidirectional per-keystroke sync**: every keystroke ran a full-document `parseBack` + a full-document re-flatten (whose `NSAttributedString` was discarded — only the selection maps were kept), pushed the document through the binding into the reducer, and every reducer-driven structural edit (Enter, exit-list, every format command) re-flattened and **wholesale-replaced** `textView.attributedText`. The named fixes accumulated across the branch (B1, B3, B7, C1–C3, L1, M2, S2–S4) were all patches on invariants of that seam. The seam does not converge: character edits flowed textview-first (parse-back infers the document), structural edits flowed document-first (flatten pushes down) — two writers in opposite directions, reconciled by inference.

Wholesale replacement also broke three things this EDD elsewhere depends on:
- **§17.5 undo** assumes `UITextView.undoManager` native undo for in-block edits. Replacing `attributedText` destroys the native undo stack on every Enter and every format command.
- **IME / marked text**: replacement mid-composition breaks CJK input, dictation, and Scribble — the latter is load-bearing for the Pencil story.
- **Incremental layout**: every Enter forced a full TextKit re-layout of the document.

**The revised rule mirrors the canvas boundary** (`CLAUDE.md` "Canvas + TCA boundary", view layer EDD §10): *TCA owns commands, configuration, and persistence; `NSTextStorage` owns live text imperatively.*

- **Typing** stays in UIKit. `textViewDidChange` does no full-document work; the document syncs to the reducer **debounced** (idle), and immediately on **structural** change (paragraph count delta — Enter, paste-with-newlines, multi-paragraph delete).
- **Commands** (inline format, block format, exit-list, paragraph split) are applied as **text-storage surgery** in the Coordinator — incremental edits that preserve native undo, marked text, and incremental layout. The reducer still receives the same actions for state + effects (persist, palette); the *application* moves to the imperative side — exactly like `PaperMarkupViewController` owning strokes while TCA gets `.strokeCompleted`.
- **Parse-back is no longer inference.** All structural mutations assign fresh `blockID`s in the storage at edit time, so parse-back reads authoritative IDs instead of heuristically deduping collisions.
- **Selection bridging** reads `.blockID` at the caret (paragraph-local scan) + a cached leaf-id→path index rebuilt only on structural sync — no per-keystroke flatten-map rebuild.
- **Slash filter** is computed Coordinator-side from the storage text after the pinned trigger location, emitted as a lightweight event — the palette no longer needs a per-keystroke document mirror.

The persisted model (`RichTextDocument`), the reducer's persistence/palette contracts, `BlockDecoratingLayoutManager`, and the test suite all survive; only the sync *flow* changes. NoteRegion text anchors (Phase 6 / §11) get *stronger* under this rule: block IDs are assigned at edit time, not recovered by inference.

### 22.5 Phase 3 (continued) — text editing chrome

9. **Caret-anchored slash popover** — replace fixed-corner positioning with `UIPopoverPresentationController` anchored at the editor's caret rect on iPad regular / Mac. **SHIPPED — with a known coupling (2026-06-10):** the scroll-tracking machinery (`pinnedSlashLocation`, `scrollViewDidScroll` rect republish) assumes the editor's `UITextView` owns scrolling (`isScrollEnabled = true`). Phase 5's `PageBlockStackView` moves scroll ownership to the stack container, which invalidates this subsystem — budget a rework of the anchor-tracking path (likely: observe the stack's scroll view instead) as part of commit 23.
10. **`TextAccessoryBarView`** — iPhone + iPad compact soft-keyboard accessory bar with mode switching + Aa popover (§14.4).
11. **`UIKeyCommand` set** — ⌘B/I/U/⇧⌘K/⌘⌥1-3/⌘⌥0/⌘⇧7-9/⌘⇧D/⌘⇧/ wired to the same reducer actions as the slash menu.
12. **`NSMenu` set** on Mac (parallel to UIKeyCommand).
13. **Selection menu extensions** — `UIEditMenuInteraction` adds Mark Region, Highlight ▸, Send to Dispatch; `NSMenu` mirrors on Mac.

### 22.6 Phase 4 — voice blocks

14. `SpeechService` dependency (live + test).
15. Scenario B first — `VoiceBlockView` + capture flow + permission integration.
16. Scenario A — `/dictate` slash command + accessory bar mic icon insert into the active text block.
17. Scenario C — Transcribe action on a voice block creates a seeded text block linked via `sourceVoiceBlockID`.
18. Home-screen voice-first surface + Siri shortcut.
19. Tests: each scenario's reducer flow, mocked SpeechService.

### 22.7 Phase 5 — hybrid composition (iPad ink + text in one page)

20. `InkBlockView` (per-block PKCanvasView at canonical scale, §6).
21. `DragBarView`.
22. `PageBlockStackView` (feature view interleaving per-block components with drag bars). Each kind is its own SwiftUI view — TextBlockView, InkBlockView, VoiceBlockView, DividerBlockView (page-level), ImageBlockView (later).
23. Refactor `CanvasScreen` to render via `PageBlockStackView`. `NotePageFeature` lifts state out of `CanvasScreen`'s @State.
24. Pencil-in-blank-text → new ink block (§10.4).

### 22.8 Phase 6 — region anchor extension (text-range integration)

25. Extend dispatch panel to surface text-anchored regions identically. Most of the schema work lands in Phase 2.5; this step is the dispatch / RegionIndicator integration.

### 22.9 Phase 7 — accessibility hardening

26. Custom rotors.
27. Accessibility action names on every block kind's component.
28. CI audit test.
29. PR template update.

### 22.10 What gets deleted in the refactor

- `TextKitEditorView` (TextKit 2 version) — replaced by the TextKit 1 version.
- `SlashEditorPoC.swift` — replaced by the production editor.
- The temporary "PoC" button on `HomeWiringView.swift`.
- `AttributeScopes.FromInkAttributes` — superseded by the `Mark` enum and NoteRegion-fielded text anchors.
- `RegionAnchorAttribute`, `HighlightAttribute`, `SlashInsertionAttribute` AttributedString scope keys — replaced by document-level concepts.
- `CanvasScreen`'s per-page header/link/region local `@State` (collapses into `NotePageFeature` in Phase 5).
- Legacy `NoteHeader` + `NoteLink` consumer paths (Phase 5).
- `CanvasScreen.headerPreviewImages` (Phase 5).

---

## 23. Open questions

| # | Question | Required by |
|---|---|---|
| Q1 | LWW per block is the v1 strategy. When do we revisit CRDT for concurrent text editing in the same block? | When multi-device usage telemetry shows non-trivial conflict rates. |
| Q2 | Hybrid maximum scale cap of 1.5× — does this feel right on a 27" Studio Display? Pure-ink uncapped is fine, but hybrid may want a user-set zoom preference. | Mac large-window UX review. |
| Q3 | Voice block confidence per-word display — is the dotted-underline-on-low-confidence treatment overstimulating? Should it be opt-in? | User testing post-Phase-4. |
| Q4 | Home-screen voice-first surface — should it become the default capture path for users who set it that way (replacing the new-note "+" button on home)? | After Phase 4 ships, consult on home screen UX. |
| Q5 | Read-aloud action — should highlights affect speech (pause, color-named callout) or be silent? Same question for regions. | Accessibility user research. |
| Q6 | Pencil-in-blank-text auto-promotion to ink block — should we add a setting to disable for users who don't want it? | Beta feedback. |
| Q7 | Block-level diff for FM input — do we send the whole `extractedText` on every change, or just the changed block? Latter is cheaper but FM may produce worse results with less context. | When summarization budget becomes a concern. |
| Q8 | Should `image` and `embed` block kinds ship in v1 or wait for v1.1? Architecture supports them either way. | Product prioritization. |
| Q9 | ActivityKit Live Activity for voice capture — v1 or follow-up? | Engineering capacity. |
| Q10 | Multi-window on Mac/iPad — does opening the same note in two windows present any state-sync risk beyond LWW? | After Phase 5. |
| Q11 | Image and video block kinds — slot into the same block stack (commented-out enum cases already noted in §5). Picker surfaces, storage caps for video (60s / 100MB cap recommended), and caption story all defer to v1.1. | Post-v1. |
| Q12 | When iOS 27 adoption is high enough, evaluate single-pass multimodal Foundation Models for the OCR + extraction pipeline (image → `@Generable` SessionOutput in one call). Current two-stage (Vision → text → FM) ships unchanged on iOS 26; multimodal is purely an optimization opportunity for v1.1+. | iOS 27 adoption telemetry. |

---

## 24. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-06-07 | Hybrid pages (text + ink interleaved) as the primary model. | Matches user expectation post-iOS 26 Notes; mode-per-page sidesteps the problem instead of solving it. |
| 2026-06-07 | TextKit 2 + AttributedString as the text engine. | TextKit 2 is the only path to a custom layout pass that knows about ink blocks; AttributedString is the natural Swift data model. |
| 2026-06-07 | Block-based document model (`PageBlock`). | Localizes CloudKit conflicts; gives natural VoiceOver reading order; lets text and ink coexist without coordinate transformations between layers. |
| 2026-06-07 | Unified `NoteRegion` with `.inkRect` / `.textRange` anchor discriminator. | One dispatch surface, one indicator component, one lifecycle. Text-range anchor rides on AttributedString custom attribute so it survives edits for free. |
| 2026-06-07 | Canonical canvas (per-notebook, bound on first stroke to the authoring device's portrait width) for ink storage; viewport-relative scale at render time. | Authoring is always 1:1 on the originating device; cross-device anchors stable; PencilKit-native. Default 768pt for empty notebooks. |
| 2026-06-07 | Drag bar is the visual handle for `PageBlock.heightPoints`. | The Apple Notes pattern; trivially fits the block model; accessibility action exposes the equivalent for non-gesture users. |
| 2026-06-07 | Slash menu available on Mac + iPad regular; size-class gate (not platform gate). | iPad in Slide Over is visually iPhone; treating it as such keeps UX consistent. |
| 2026-06-07 | Slash menu single-row mode-switching on iPhone, with one popover concession (`Aa` for dense formatting). | 44pt vertical budget doesn't fit dense menus; the Apple Notes pattern is the proven solution. |
| 2026-06-07 | `/` never intercepted on iPhone. | Plane-switch tax + accessory bar exists + Apple Notes precedent. |
| 2026-06-07 | Voice memo as first-class `PageBlock.kind = .voice`. | Parallel to text/ink; audio + transcript pair gives both fidelity and search; ADA-tier inclusion feature. |
| 2026-06-07 | Voice-first capture as a home-screen surface. | The inclusion-as-polish move; not buried in a menu. |
| 2026-06-07 | On-device speech recognition only (`requiresOnDeviceRecognition = true`). | Privacy principle from `CLAUDE.md`; iOS 26's on-device recognizer is good enough. |
| 2026-06-07 | LWW per block as the v1 sync conflict strategy. | Block model localizes conflicts; CRDT is deferred as an open question, not foreclosed. |
| 2026-06-07 | Custom rotors for Regions, Headings, Voice memos, Attachments. | Power feature for VoiceOver users; low implementation cost; ADA shortlist signal. |
| 2026-06-07 | Color is never the only signal — highlights and regions always carry an icon overlay. | Differentiate Without Color compliance; protects colorblind users without a separate code path. |
| 2026-06-07 | Reducer-action vocabulary IS the command vocabulary. One reducer, many chromes. | Voice Control "works for free"; testability; modularity. The thesis of the EDD. |
| 2026-06-08 | No migrations until CloudKit ships. Schema changes land directly; dev simulator resets if store fails to open. | Pre-production with `cloudKitDatabase: .none`; the user has stated this rule explicitly. Reverts to standard `VersionedSchema` discipline once CloudKit promotes to Production. |
| 2026-06-08 | Slash menu gates on (hardware-keyboard connected OR `horizontalSizeClass == .regular`) — hardware keyboard always wins. | Closes the iPad-compact-with-hardware-keyboard gap where neither surface would otherwise be available. |
| 2026-06-08 | Drag bar visible only when ink is authorable (iPad regular with Pencil-capable hardware). | Read-only drag bar was a contradictory UX; ink is read-only on iPhone / Mac / iPad compact, so its sizing handle is hidden too. |
| 2026-06-08 | Per-block PKCanvasView lifecycle (placeholder / thumbnail / live) with active-range buffer. | All-live canvases land 80–200MB on long pages; viewport-buffered lifecycle keeps memory bounded to ~15MB regardless of page length. |
| 2026-06-08 | `⌘⇧/` (not `⌘/`) opens the slash menu. | `⌘/` is "Show All Help" on Mac and not overridable. |
| 2026-06-08 | Undo is page-scoped with a native-first cascade (text/ink block native managers → page-level reducer stack). | Apple Notes' model; native handles in-block edits without double-counting via reducer entries. |
| 2026-06-08 | Per-block `contentHash`; `NotePage.extractedTextHash` aggregates from the manifest of per-block hashes. | Reorders no longer invalidate ML caches when no content changed; deltas are computable for FM re-runs. |
| 2026-06-08 | Image and video block kinds deferred to v1.1; architecture supports the addition. | Avoids scope creep on v1 while making the architectural seam explicit. |
| 2026-06-08 | SwiftUI `TextEditor` + `AttributedString` (iOS 26 rich text APIs) is the primary text engine; UIKit `UITextView` bridge over TextKit 2 is the documented fallback. | Apple's iOS 26 rich-text editing APIs (WWDC25 session 280) cover our requirements natively; the UIKit wrapper is meaningful code we avoid writing if the spike passes. |
| 2026-06-08 | Prefer `AttributedString` Codable (Path B) for block body serialization; fall back to `NSKeyedArchiver` (Path A) only if a custom attribute drops in round-trip. | Native to the `TextEditor` APIs and `AttributeScopes`; one encoding system through the editor and storage. |
| 2026-06-08 | `SpeechService` targets `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26); `SFSpeechRecognizer` is the fallback only for unsupported locales. | The new framework is materially better for long-form transcripts (~2× faster, higher quality), which is the load-bearing voice-memo UX. |
| 2026-06-08 | Multimodal Foundation Models (iOS 27, image input) parked as an open question for v1.1 OCR pipeline replacement; v1 ships the existing two-stage pipeline unchanged. | We target iOS 26 for v1; multimodal is a pure optimization, not a v1 dependency. |
| 2026-06-08 | No Liquid Glass anywhere in the app — opaque paper-and-ink chrome only. | Brand decision; preserves the editorial aesthetic. See user memory `feedback_no_liquid_glass.md`. |
| 2026-06-09 | TextKit 1 hand-built stack (`NSTextStorage` → `BlockDecoratingLayoutManager` → `NSTextContainer` → `UITextView(frame:textContainer:)`) replaces SwiftUI `TextEditor` / TextKit 2 as the editor engine. | Manual verification: neither `TextEditor` nor TextKit 2 `UITextView` paints block-level structure; `drawBackground(forGlyphRange:)` only fires under TextKit 1. (TextKit 2's `NSTextLayoutFragment.draw(at:in:)` via the layout-manager delegate is the documented modern alternative — known and deliberately not chosen for v1.) Supersedes the 2026-06-08 `TextEditor` decision. |
| 2026-06-10 | **Imperative text boundary** — TCA owns commands, configuration, and persistence; `NSTextStorage` owns live text. No per-keystroke parse-back/flatten; commands apply as incremental storage surgery; document syncs debounced (typing) or immediately (structural change). | Mirrors the canvas boundary. The bidirectional per-keystroke sync was the root cause of the B*/C*/L*/M*/S* fix series, broke native undo (§17.5 dependency), and risked IME/Scribble breakage. See §22.4.1. |
| 2026-06-10 | `PageBlock.bodyData` storage representation (inline vs `.externalStorage`) is decided jointly with block granularity, before the CloudKit Development schema exists. | The inline decision assumed 200B–2KB paragraphs-per-block; the current editor stores a whole page's document in one block, which can approach CloudKit's 1 MB record limit. See data_model_edd §9 pre-flip checklist item 1. |
| 2026-06-10 | `NotePage.extractedText` / `extractedTextHash` are local derived caches, not sync-authoritative fields; recompute on remote-change import. | Per-record LWW on a denormalized aggregate yields an aggregate reflecting neither device's merged block state. See data_model_edd §9 pre-flip checklist item 2. |
