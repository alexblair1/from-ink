# Text Editor — Readiness Audit

**Date:** 2026-07-06
**Scope:** The text editing flow (`TextKitEditorView`, `TextEditingFeature`, `TextBlockView`,
`TextNoteWiringView`, slash palette, accessory bar, `ParagraphIndex`, `PageBlock` persistence)
audited ahead of notebook integration planning. Goals being planned against: hybrid text + ink
pages on iPad, text editing on iPhone, text editing on Mac.

**Verdict at audit time: not integration-ready.** The single-note iOS editing core is strong —
sound imperative boundary (EDD §22.4.1), ~240 passing tests — but four mission-critical
correctness risks, a set of accessibility/design gaps that get more expensive after per-block
embedding, and two platform gaps (Mac empty, hybrid unbuilt) need burn-down first.

Line numbers reference the tree at commit `0f15c57`.

---

## A. Mission-critical bugs

| ID | Status | Summary |
|---|---|---|
| A1 | **fixed** (this branch) | No storage-alignment guard in sync path → silent document corruption |
| A2 | **fixed** (this branch) | Composition commit of structural change corrupts `ParagraphIndex` |
| A3 | **fixed** (this branch) | No scenePhase flush — typing lost on backgrounding/kill |
| A4 | **fixed** (this branch) | Persist failure never retries; no `bodyData` size guard |
| A5 | **fixed** (this branch) | Duplicate text-block seeding race on double `onAppear` |

### A1 — No storage-alignment guard → silent document corruption *(verified)*

`ParagraphIndex` is maintained only through edits captured in
`textView(_:shouldChangeTextIn:replacementText:)`. Any edit that bypasses that delegate mutates
storage while the index goes stale, and `syncDocumentFromStorage` ran `documentFromIndex`
with **no alignment check** — `paragraphCount(in:)` existed (`TextKitEditorView.swift:1173`)
but was never called in production. A misaligned index zips wrong ranges into a wrong
`RichTextDocument`, which then persists to SwiftData. Corruption, not a display glitch.

Confirmed bypass paths:
- **Undo of native typing** — undo of Enter is structural and nothing re-registers it.
- **Scribble** (Apple Pencil writing into the text view) — neither handled nor disabled.
- Composition-commit edge (A2), edit-menu Replace, some drop interactions.

**Fix:** alignment guard before `documentFromIndex`; on mismatch, rebuild the index from
storage (`ParagraphIndex(storage:)`) accepting fresh identity, instead of producing a corrupt
document. Scribble explicitly disabled for v1 (see D5).

### A2 — Composition commit corrupts the index

`shouldChangeTextIn` clears all pending edit captures while `markedTextRange != nil`. If the
committed composition contains a newline, the structural sync runs with
`pendingStructuralEdit == nil` → same stale-index corruption family as A1. Covered by the A1
alignment guard.

### A3 — Data-loss window on backgrounding / process kill

Typing sits in a 300ms editor debounce plus the reducer's persist debounce, with no scene-phase
hook. Routine dismissal was already covered (`.flush` on disappear retries while `isDirty`;
persist effects outlive the view on the root store), but swipe-to-background or process kill
inside the window lost the last ~1s of typing.

**Fix:** Coordinator flushes storage → binding on `UIApplication.willResignActiveNotification`;
`TextNoteWiringView` sends `.textEditing(.flush)` when `scenePhase` leaves `.active`.

### A4 — Persist failure: one banner, no retry; no size guard

`persistFailed` (`TextEditingFeature.swift:222`) set the banner and stopped. Retry happened only
on the next edit or the dismiss flush; a persistent failure silently dropped everything after
the banner. Separately, `PageBlock.bodyData` is deliberately not `externalStorage` and had no
size guard against CloudKit's ~1MB per-record limit.

**Fix:** scheduled delayed retry after failure (cancelled/superseded by any newer persist),
plus an encoded-size warning log at 750KB.

### A5 — Duplicate-seed race

Double `onAppear` before the first `insertBlock` completes could seed two text blocks
(`NotebookFeature.swift` `textBlocksLoaded` had no in-flight guard).

**Fix:** `isSeedingTextBlock` in-flight flag; the seed result routes through a dedicated
`textBlockSeeded` action that clears the flag, re-arms on failure, and refuses to hand the
editor a block for a page the user has swiped away from.

---

## B. UI/UX bugs & design debt

All inside the editor internals — fix while there is exactly one editor instance, before
per-block embedding multiplies the surfaces.

| ID | Severity | Summary | Where |
|---|---|---|---|
| B1 | **fixed** (this branch) | iPhone/compact + soft keyboard now gets a **literal slash** — the typed-slash trigger is gated by `typedSlashOpensPalette` (regular size class OR hardware keyboard, per EDD §13.3's "hardware keyboard wins"); `⌘⇧/` path untouched | `TextKitEditorView` slash trigger path |
| B2 | **fixed** (this branch) | Headings now scale via `UIFontMetrics` (title1/2/3 curves, same sizes at default content size). Remaining: fonts snapshot at editor creation — a mid-session Dynamic Type change needs a re-flatten hook (rare; app relaunch covers it) | `scaledSerif` |
| B3 | **partial** (this branch) | Headings now carry `.accessibilityTextHeadingLevel` (VoiceOver announces "heading level N", rotor navigation works; kept in step on demote via `reStampIdentity`). Remaining: list bullets/ordinals are still drawn chrome, invisible to VoiceOver — the real fix is marker glyphs as characters, deferred to the hybrid text refactor | `paragraphContent` / `reStampIdentity` |
| B4 | **fixed** (this branch) | Ordinal digits localize via `orderedListMarkerText(_:locale:)` (Arabic-Indic, Devanagari, …); marker gutter mirrors for RTL via `markerOriginX(isRTL:)` reading the view's live layout direction. Head-indents were already direction-relative (NSParagraphStyle) | layout manager |
| B5 | **fixed** (this branch) | All chrome + content colors tokenized: `BlockChromeColors` (blockquote bg/bar, code bg, divider rule, list marker) injected into the layout manager; link + 4 highlight tokens replace the `systemBlue`/`systemYellow…` literals. Ten new `ink/*` color sets with baked alphas + dark variants | `ColorTokens`, `BlockChromeColors` |
| B6 | **fixed** (this branch) | `keyCommands` HUD titles now come from `AppStrings.AccessoryBar`, reusing the accessory-bar vocabulary (⌘⌥1/2/3 read Title/Heading/Subheading, matching the Aa popover); new `slashMenu` key | `BlockTreeTextView.buildKeyCommands` |
| B7 | UX-minor | Inline toggles silently no-op in code blocks while chips still look tappable | `applyInlineToggleAtCaret` |
| B8 | UX-minor | Slash palette always opens with Heading 1 highlighted; no context awareness | `SlashCommandPaletteFeature.openRequested` |

Correction recorded from the audit: the accessory bar **is** wired — installed as
`inputAccessoryView` in `makeUIView` (`TextKitEditorView.swift:181`), on all size classes.
The iPhone gap is B1 only, not bar wiring.

---

## C. Platform & integration readiness

| Area | Status | Reality |
|---|---|---|
| iPad, single text note | **Ready** | Keyboard shortcuts, palette, accessory bar all work; well tested |
| iPhone | **Partial** | Bar works; needs B1 (compact slash gating) + a real-device keyboard-inset pass |
| Mac | **Missing** | `TextBlockView` renders read-only `Text(plainText)`; the entire TextKit stack is `#if os(iOS)`-gated. Full parallel NSTextView implementation ≈ its own workstream |
| Hybrid text + ink | **Missing** | Schema ready (`PageBlock` kind/sortIndex, CloudKit-compliant; `NotePage.blocks` cascade). Unbuilt: `NotePageFeature`, `PageBlockStackView`, ink block lifecycle (placeholder/thumbnail/live), DragBar, focus management, page-level undo |

### Integration seams to design for (not discover)

1. **Scroll ownership** — editor is `isScrollEnabled = true`; the hybrid block stack owns the
   outer scroll. Slash-anchor tracking is explicitly coupled to inner scroll (EDD §22.5.9
   flags this itself). Budget the rework.
2. **Singular-state assumptions** in `TextEditingFeature` — one `document` / `selection` /
   `slashPalette` / `activeBlock`. N text blocks per page needs per-block scoping or an
   active-block-swap model.
3. **Undo** — one native `undoManager` per UITextView; page-level undo across text + ink
   blocks needs an aggregation design.
4. **Either/or variant switch** — `NotebookScreen.swift:~101` assumes a notebook is text *or*
   canvas; hybrid dissolves that.

---

## D. Recommended sequence

1. **Correctness hardening (A1–A5)** — *done on this branch.* Includes the Scribble decision:
   disabled for v1 (D5).
2. **iPhone compact gating (B1)** — *done on this branch.*
3. **Editor-internal debt (B2–B6)** — *done on this branch* (B3 partial: heading semantics
   shipped; list-marker VoiceOver visibility deferred to the hybrid marker-glyph refactor).
4. **Hybrid foundation** — `NotePageFeature` + `PageBlockStackView` + ink lifecycle as its own
   planned phase; the seams in §C are the open design questions.
5. **Mac scope decision** — read-only Mac is shippable v1; full authoring is a separate
   workstream, not a bug to fix. *(D5 note: Scribble disabled in v1 — Pencil authors ink,
   not typed text. Revisit when hybrid pages land; proper support means routing Scribble
   edits through the index-maintenance path.)*

### Test-coverage gaps to close alongside

- Native-typing undo (especially undo of Enter)
- Composition-commit structural edits
- Persist-failure retry policy
- Double-seed race (A5)
- Dynamic Type / RTL snapshot variants
