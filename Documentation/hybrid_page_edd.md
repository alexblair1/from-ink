# Hybrid Page EDD — Text + Ink Block Stack

**Status:** DRAFT — for review
**Date:** 2026-07-06
**Depends on:** `text_experience_edd.md` (§5–6 block model, §13–14 command surfaces, §22
execution log), `text_editor_readiness_audit.md` (steps 1–3 complete on `main` at `44b3d74`),
`data_model_edd.md` (CloudKit rules)

## 1. Purpose and scope

This document designs the migration from today's **either/or** page model (a notebook is
entirely ink OR entirely text, switched at `NotebookScreen.swift:~101`) to the **hybrid block
stack** the text experience EDD specifies: text blocks and ink blocks interleaved vertically on
one page, on iPad first.

It is a *migration* design. The text experience EDD describes the destination; this document
decides the four seams the readiness audit flagged, resolves the open v1-shape question, and
sequences the work so the hardened single-block editor (audit steps 1–3) never regresses on
the way.

Out of scope: Mac authoring (audit step 5, separate workstream), voice blocks (schema exists;
UX deferred), NoteRegion text anchors, multi-block text selection.

## 2. What already exists (verified against `main` @ `44b3d74`)

The foundation is further along than "missing" suggests — the *data and persistence layers are
done*; the *reducer and view layers are not*.

| Layer | Status | Evidence |
|---|---|---|
| Schema | **Ready** | `PageBlock` (`id`, `sortIndex`, `kindRaw` text/ink/voice, `heightPoints`, `bodyData`, `drawingData`+`thumbnailData` externalStorage, `ocrText`, `contentHash`); `NotePage.blocks` cascade relationship; CloudKit rules obeyed |
| Persistence API | **Ready** | `NotebookClient`: `fetchBlocksForPage`, `insertBlock`, `deleteBlock`, `reorderBlocks`, `updateBlockBody`, `updateBlockDrawing`, `updateBlockOCR`, `updateBlockHeight`, `loadBlockDrawing`, `bindCanonicalCanvasWidth` |
| Aggregation | **Ready** | `NotePage.extractedText` composes per-block payloads in `sortIndex` order for the dispatch pipeline |
| Text editor | **Ready (hardened)** | `TextKitEditorView` + `TextEditingFeature`: index alignment guard, backgrounding flush, bounded persist retry, seed guard, compact slash gating, Dynamic Type, tokens, RTL |
| Ink rendering | **Legacy path** | `CanvasScreen` renders full-page ink via `CanvasViewBridge` against `NotePage.drawingData` (legacy fields, documented to retire at the carve-up) |
| Page reducer | **Missing** | No `NotePageFeature`; `NotebookFeature` scopes one `TextEditingFeature` and assumes one block per textNote page |
| Block stack view | **Missing** | No `PageBlockStackView`, no `InkBlockView`, no `DragBarView` |
| Ink lifecycle | **Missing** | No placeholder/thumbnail/live states, no viewport observer |

## 3. The four seam decisions

These were flagged in the readiness audit as "design for, don't discover." Each gets a
decision here, with the alternative recorded.

### 3.1 Scroll ownership → the STACK owns scrolling

**Decision.** `PageBlockStackView` is a `ScrollView` (SwiftUI) owning the page's single
vertical scroll. Text block editors become **non-scrolling, self-sizing** views:
`isScrollEnabled = false`, height driven by TextKit's `usedRect` reported up through a
preference/callback so the stack allocates exactly the content height.

**Why.** Two nested scrollables on the same axis is gesture ambiguity (the wiring view already
documents this jank class). The EDD's block model — scroll position preserved as a fraction of
page height, ink blocks scrolling in the same plane as text — only works with one scroll owner.

**Consequences to budget:**
- `BlockTreeTextView.layoutSubviews` width management survives unchanged (width still comes
  from bounds). Height must stop being "fill" — the editor reports
  `layoutManager.usedRect(for:).height + insets` after layout and the stack sets the frame.
- **Slash popover anchor tracking reworks** (EDD §22.5.9 flagged this): today the Coordinator
  republishes the caret rect from `scrollViewDidScroll` of its own textView. With outer
  scroll, the anchor must convert editor-local rects into stack-scroll space and republish on
  the STACK's scroll. Plan: the wiring layer owns an `onScrollGeometryChange` observer on the
  stack and re-derives the anchor from (block frame in stack) + (caret rect in block).
- **Caret keyboard avoidance** stops being free (UITextView does it when it owns scroll).
  The stack must scroll-to-caret on selection change when the caret would sit under the
  keyboard/accessory bar. `ScrollViewProxy.scrollTo` + caret-rect reporting covers it.

**Alternative rejected:** keep per-editor scroll and give ink blocks their own cells inside a
`List`. Rejected because mixed scroll owners break the single-page feel, drag-to-reorder, and
fraction-based scroll restoration.

### 3.2 Text editing state → ONE live editor, active-block swap

**Decision.** Keep exactly **one** `TextEditingFeature` instance (scoped under
`NotePageFeature`), pointed at the active text block — the *active-block-swap* model the
feature's `activeBlockChanged` action already implements. Non-active text blocks render as
**static text** (flatten the `RichTextDocument` to an attributed string into a non-editable,
non-scrolling `UITextView` sharing the same `BlockDecoratingLayoutManager` so chrome renders
identically — or the same editor view in a locked mode; decide at implementation by profiling).

**Why.** Everything hardened in audit steps 1–3 (index alignment, flush ordering, persist
retry, slash gating) lives in one Coordinator + one reducer. N live TextKit stacks means N
Coordinators, N debounce timers, N undo managers, N accessory-bar claims — and none of it buys
anything: only one block can have the keyboard. One live editor ≈ 500KB; static renders are
cheap. This also mirrors the ink lifecycle (one live canvas in the edit path).

**Swap protocol (the critical correctness sequence):**
1. Tap on non-active text block → `NotePageFeature.blockActivated(id)`.
2. Reducer sends `.textEditing(.flush)` for the outgoing block (persist current content;
   the editor's teardown flush covers the debounce tail — same path as page swipe today).
3. Reducer loads the incoming block's snapshot → `.textEditing(.activeBlockChanged(snap))` —
   which already resets document/selection/palette/dirty state and cancels stale persists.
4. Focus (first responder) moves to the new editor instance.

`activeBlockChanged`'s existing same-block-echo guard and the A5-style stale-page guard carry
over; add a stale-*block* guard: a snapshot landing for a block that is no longer
`activeBlockID` is dropped.

**Alternative rejected:** `IdentifiedArrayOf<TextEditingFeature.State>` with per-block scoping.
Correct in principle, but multiplies every hardened invariant across N instances and forces
the accessory bar/undo/keyboard questions immediately. Revisit only if active-swap feels
laggy in practice (it shouldn't: swap cost = one flatten of the incoming document).

### 3.3 Undo → per-block native undo in v1, page aggregation deferred

**Decision.** v1 hybrid keeps the current model: native `UITextView` undo for in-block text
edits (already undo-registered via `replaceCharactersRegisteringUndo` + native typing), and
PencilKit's own undo inside the live ink block. Undo applies to the **focused block**. The
accessory bar's undo button routes to the active editor's `undoManager` (unchanged).

Structural page operations (insert block, delete block, reorder, height change) are **not
undoable in v1** — same as today, where they don't exist at all. Deleting a non-empty block
gets a confirmation instead of relying on undo.

**Why.** Page-level undo across heterogeneous blocks (text + ink) requires an aggregating
undo stack with block-scoped entries and cross-block focus restoration — a real design, and
one that gets *easier* after the stack exists (the aggregation point, `NotePageFeature`, will
be there). Blocking hybrid v1 on it inverts the dependency. The cost is honest: undo after
switching blocks acts on the new block, not the last edit globally. Apple Notes users expect
document-wide undo, so this is a known v1 gap — logged in the audit doc as a hybrid follow-up.

### 3.4 Focus + keyboard accessory → active block owns both

**Decision.** `NotePageFeature.State.activeBlockID: UUID?` is the single focus authority.
- Tap a text block → active; its editor becomes first responder; the accessory bar comes with
  it for free (it's the editor's `inputAccessoryView` — already installed per-editor, and only
  one editor is live, so ownership is automatic).
- Tap an ink block → active; keyboard resigns; Pencil tools apply.
- The active text block gets a subtle affordance (1px `rule` border per the design system — no
  shadows, no color).
- `activeBlockID` survives rotation (EDD §6.6 state-preservation list) alongside the
  scroll fraction.

### 3.5 Block creation at boundaries — both directions

The core hybrid promise is symmetric: **handwriting below a block of text, and text below
handwriting.** Both flows are first-class requirements of Phase 3 and acceptance criteria for
calling hybrid "done."

**Ink below text (specified in the parent EDD — adopted as-is).** Pencil-down on a blank
line inside a text block splits the text at that point and inserts an ink block between the
halves; the stroke begins recording immediately (`text_experience_edd.md` §10.4,
`.inkBlockInserted(afterBlockID:)`; §15.1 implicit-input table). Pencil-down in the empty
region BELOW the last block appends an ink block at the end of the page — same action, `after:
lastBlock.id`. No mode switch, no button: the Pencil *is* the intent (Apple Notes convention).

**Text below ink (new — the parent EDD leaves this unspecified).** The inverse rule, using
the same "the input device is the intent" principle:

| Gesture | Effect |
|---|---|
| Finger tap in the empty region below the last block (when last block is ink) | Append a text block, activate it, keyboard up, caret at start |
| Finger tap in the gap between an ink block and the next block | Insert a text block at that boundary, activate it |
| Accessory bar / end-of-ink affordance (explicit fallback) | Same insert, for discoverability and for Pencil users who want text next |
| Keyboard input while an ink block is active (hardware keyboard case) | Append/insert a text block after the active ink block and route the keystroke into it — typing always has somewhere to go |

Both directions reduce to the ONE reducer action the architecture already carries —
`insertBlockRequested(kind:after:)` — so the symmetric UX costs no new state machinery. Empty
auto-created blocks that lose focus without receiving content are reaped (no stranded empty
blocks from an exploratory tap), mirroring the seed-block hygiene from audit A5.

## 4. The v1 shape question, resolved

**Question from the audit:** does v1 hybrid keep the full-page canvas as ONE big ink block, or
go straight to interleaved ink blocks?

**Decision: one ink block per page at cutover, interleaving as the immediately-following
phase — on the same architecture.** Concretely: the block stack is built for N blocks from day
one, but the *migration writes* existing pages as `[ink block (full page)]` or
`[text block]`, and the insertion UX (the thing that creates a second block) lands one phase
later. This is not the "cheap hack" version — it is the target architecture with the content
migration de-risked:

- The stack, `NotePageFeature`, lifecycle, and focus model are identical for 1 and N blocks —
  nothing is thrown away.
- Existing notebooks cut over losslessly: legacy `NotePage.drawingData` → one ink block's
  `drawingData`; `textNote` pages already write through `PageBlock.bodyData`.
- Ink-block internals (canonical width + `scaleEffect`, EDD §6.4; `bindCanonicalCanvasWidth`
  already exists) get proven on the single-block case where regressions are obvious, before
  interleaving multiplies them.
- Per the data model EDD, no SwiftData migration machinery: the cutover commit moves payloads
  in application logic on first open (read legacy field → write block → clear legacy), and
  legacy fields retire in the same commit that lands per-block ink rendering (the plan
  `NotePage.swift` already documents).

## 5. Architecture

### 5.1 Feature composition

```
NotebookFeature                      (unchanged: page list, swipe, toolbar, variant resolve*)
  └── NotePageFeature                (NEW — one per visible page)
        State:
          pageID: UUID
          blocks: IdentifiedArrayOf<BlockRow>        // value-type row per block
          activeBlockID: UUID?
          scrollFraction: Double                     // rotation/restore
          isSeedingBlock: Bool                       // A5 guard, lifted from NotebookFeature
        Child:
          textEditing: TextEditingFeature.State      // the ONE live text editor
        Action (selection):
          blocksLoaded([PageBlockSnapshot])
          blockActivated(UUID)
          blockEnteredWarmRange(UUID) / blockExitedWarmRange(UUID)   // ink lifecycle
          blockDrawingLoaded(UUID, Data)
          blockHeightChanged(UUID, Double)           // drag bar (later phase)
          insertBlockRequested(kind: PageBlockKind, after: UUID?)
          deleteBlockRequested(UUID)
          textEditing(TextEditingFeature.Action)
```

`BlockRow` is a plain value: `id`, `kind`, `sortIndex`, and a *render payload* —
`.text(RichTextDocument)` for static rendering, `.ink(InkBlockLoadState)` per the EDD's
placeholder/thumbnail/live enum. `@Model` objects never enter state (project rule); rows are
derived from `PageBlockSnapshot`.

*`NotebookFeature.textEditing` and the textNote-specific block loading move DOWN into
`NotePageFeature`; the `.textNote` variant becomes "a page whose only block is text" rendered
by the same stack. The `NotebookScreen` either/or switch collapses to: resolved → stack.

### 5.2 View composition (three-tier, per the view layer EDD)

```
NotePageWiringView(store:)                      // TCA boundary
  └── PageBlockStackView(model:)                // Feature view — ScrollView + LazyVStack
        ├── TextBlockRowView                    //   active → TextKitEditorView (live)
        │                                       //   inactive → static attributed render
        ├── InkBlockRowView                     //   placeholder | thumbnail(UIImage) | live(PKCanvasView)
        └── DragBarView                         //   (phase 5) between-block height handle
```

The imperative boundary holds: strokes stay inside the live `PKCanvasView`'s bridge; keystrokes
stay inside the live editor's Coordinator; the reducer sees completed intents (EDD §22.4.1).

### 5.3 Ink block lifecycle (EDD §6.4.1, unchanged from spec)

Placeholder (reserve height only) → thumbnail (static UIImage from `thumbnailData`) → live
(PKCanvasView). Active range = viewport ±1 block; warm = ±2 more; editing override keeps the
active block live. Promotions debounce 100ms. Demotion (`live → thumbnail`) flushes through
the existing `CanvasViewBridge.persist` path and re-renders the thumbnail. Visibility signal:
`onScrollVisibilityChange(threshold:)` per block row.

Memory target holds: 50-block page while editing ≈ 3 live canvases (~12MB) + 4 thumbnails
(~1MB) + 43 placeholders ≈ 13MB.

### 5.4 What carries over untouched

- `TextKitEditorView` internals: alignment guard, flush paths, slash gating, Dynamic Type,
  tokens, RTL markers. The only editor changes are `isScrollEnabled = false`, height
  reporting, and the anchor-tracking source swap (§3.1).
- `TextEditingFeature`: persist retry, activeBlockChanged reset semantics. Gains nothing new
  except being scoped under `NotePageFeature` instead of `NotebookFeature`.
- `NotebookClient`: the block API is already sufficient; no new client surface for phases 1–3.

## 6. Execution phases

Each phase ships independently, tests green, no regression to the previous phase. (Chunked
like the audit sequence; each phase is one or a few PR-sized commits.)

| Phase | Delivers | Key risk retired |
|---|---|---|
| **1. NotePageFeature + stack, text-only** — ✅ **DONE** (2026-07-09) | `NotePageFeature`, `NotePageWiringView`, `PageBlockStackView`; `.textNote` route moved onto it; editor non-scrolling + height-reporting (`onContentHeightChanged`, min-height floor at stack viewport); slash anchor re-sourced to stack-viewport space (`stackViewportRect` + stack-scroll KVO, popover modifier moved to the stationary stack container); caret keyboard-follow via enclosing-scroll `scrollRectToVisible`; A5 seed guard lifted into the page feature; `TextNoteWiringView` retired. Needs a real-device pass for keyboard-inset feel. | Scroll-ownership seam (§3.1) proven on the path that already has deep test coverage |
| **2. Ink cutover, one block per page** | `InkBlockRowView` (live state only), canonical-width + scaleEffect render; `.notebook`/`.quickSheet` route onto the stack; legacy `NotePage.drawingData`/`ocrText`/`typedText` payload move + field retirement; `CanvasScreen` carve-up (toolbar/dismiss chrome stays at `NotebookScreen` level per the pinned-chrome invariant) | The either/or switch dissolves; canvas parity on the new architecture |
| **3. Interleaving + insertion UX** | BOTH boundary-creation directions per §3.5 — Pencil-in-blank-text / Pencil-below-page → ink block (parent EDD §10.4), finger-tap-below-ink / keyboard-while-ink → text block; empty-block reaping; focus swap protocol (§3.2); active-block affordance; delete with confirmation | Active-block-swap seam (§3.2) + focus model (§3.4) + the symmetric creation promise (§3.5) |
| **4. Lifecycle + memory** | placeholder/thumbnail states, visibility observer, promote/demote + thumbnail refresh, scroll-fraction restore across rotation/reopen | 50-block memory target; rotation state preservation |
| **5. Drag bar + polish** | `DragBarView` height adjustment (`updateBlockHeight`), reorder, iPhone pass on the stack, snapshot coverage for block rows | Height/reorder UX |

Phase 1 is the pivotal one: it is almost pure refactor (same single text block, new owner), so
the whole scroll-ownership rework lands where the existing 232-test suite can catch
regressions. Phases 2+ add surface on a proven chassis.

### Per-phase test obligations

- **P1:** editor height reporting (content growth scrolls the stack, not the editor); slash
  popover anchor correct after stack scroll; all existing editor bundles green unchanged.
- **P2:** legacy→block payload move round-trips (drawing bytes, OCR text, thumbnails); a
  pre-cutover notebook opens identically post-cutover (snapshot).
- **P3:** swap protocol — flush-before-swap (no lost tail typing), stale-block snapshot
  dropped, palette closes on block switch. Boundary creation both directions: Pencil-on-blank-
  line splits text + inserts ink (§10.4 sequence, sortIndex integrity); finger-tap-below-ink
  appends + activates a text block; abandoned empty blocks are reaped.
- **P4:** promote/demote state machine (TestStore); scroll-fraction restore.
- **P5:** drag-bar height persistence; reorder sortIndex integrity (gapless).

## 7. Open questions for review

1. **Static text-block rendering** (§3.2): shared layout-manager UITextView (pixel-identical,
   heavier) vs. SwiftUI `Text(AttributedString(...))` (lighter, chrome must be re-derived)?
   Recommendation: locked UITextView first — pixel parity beats elegance here; profile before
   optimizing.
2. **Delete-block confirmation UX** (§3.3): branded overlay (design-system modal pattern) or
   inline two-tap? Needs a design call before Phase 3.
3. **`quickSheet` variant**: cut over with `.notebook` in Phase 2, or leave on legacy canvas
   until Phase 3? Recommendation: together in Phase 2 — one cutover, one retirement commit.
4. **iPhone**: the stack is size-class-agnostic and B1 already gates the slash surface, but
   phases 1–4 validate on iPad only; the dedicated iPhone pass sits in Phase 5. Acceptable?
5. **Page-level undo** (§3.3 deferral): confirm the v1 gap is acceptable, or promote the
   aggregating undo stack into Phase 3.
