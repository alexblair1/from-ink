# EDD — Design System

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-08 |
| Implements ticket | F-02 (design system & asset catalog) |
| Related | EDD — View Layer (consumes `Style` and `DesignSystem`); EDD — Data Layer (`UserPreferences` for future theme persistence) |

---

## Table of contents

1. [Summary](#1-summary)
2. [Goals & non-goals](#2-goals--non-goals)
3. [Why not `@Environment`](#3-why-not-environment)
4. [Token set inventory](#4-token-set-inventory)
5. [The `DesignSystem` value type](#5-the-designsystem-value-type)
6. [The injection seam — `current` and `withDesignSystem`](#6-the-injection-seam--current-and-withdesignsystem)
7. [`Style.standard` is computed, not stored](#7-stylestandard-is-computed-not-stored)
8. [Asset catalog structure](#8-asset-catalog-structure)
9. [Typography & font loading](#9-typography--font-loading)
10. [Spacing & layout philosophy](#10-spacing--layout-philosophy)
11. [What v1 ships vs. what the seam enables](#11-what-v1-ships-vs-what-the-seam-enables)
12. [Adding a new theme later](#12-adding-a-new-theme-later)
13. [Persistence of theme selection](#13-persistence-of-theme-selection)
14. [Snapshot tests for token coverage](#14-snapshot-tests-for-token-coverage)
15. [Dynamic Type & accessibility](#15-dynamic-type--accessibility)
16. [Known footguns & enforcement](#16-known-footguns--enforcement)
17. [Anti-patterns](#17-anti-patterns)
18. [Open questions](#18-open-questions)
19. [Decision log](#19-decision-log)

---

## 1. Summary

The From Ink design system is a **value-type token bundle** (`DesignSystem`) accessed through a `@MainActor`-isolated `current` accessor. Component views read tokens via their `Style` struct's `.standard` preset, which is a **computed property** that resolves through `DesignSystem.current` on every read.

v1 ships exactly one `DesignSystem` instance — `.standard`. The injection seam (`use(_:)`, `withDesignSystem(_:perform:)`) exists from day one but is exercised only by tests. Adding a high-contrast theme, a custom user theme, or any other variant later is **three lines plus a settings toggle**, with zero changes to component views or `Style` definitions.

This EDD is a companion to the View Layer EDD. It expands the design-system specifics that the View Layer EDD references in §6.

---

## 2. Goals & non-goals

### Goals

- A single source of truth for fonts, colors, spacing, and structural sizes.
- Views stay pure functions of `Model + Style` — no `@Environment` injection of design tokens.
- Tokens are testable: a snapshot test can run any view under any token set without environment plumbing.
- Adding a theme later is purely additive — no component view refactor.
- Dark mode works automatically via asset catalog references.
- The system is small enough that a solo developer can hold all of it in their head.

### Non-goals

- v1 ships no user-selectable themes. The settings UI is v2+ work.
- No mid-session theme switching in v1. Theme changes require relaunch.
- No per-platform token overrides in v1. iOS, iPadOS, and macOS share one token set.
- No third-party design-system framework (no Tailwind-for-Swift, no Stitches port). Plain Swift structs.
- Not a component library. This EDD covers tokens; components are owned by the View Layer EDD.

---

## 3. Why not `@Environment`

SwiftUI's `@Environment` is the conventional way to inject theming. We deliberately avoid it for three reasons:

1. **Pure functions of inputs.** `@Environment` introduces a hidden input channel — a view's output depends on something not visible at the call site. This breaks snapshot testing reproducibility and complicates `FeaturePreview` setup (every preview would need an environment injection step).
2. **Dark mode does not require `@Environment`.** Asset-catalog `Color` references resolve adaptively at render time regardless of how they reach the view. Whether a color arrives via a static constant, a `Model` property, or `@Environment`, it picks the correct light/dark variant automatically.
3. **One less thing to wire.** No `.designSystem(.standard)` at the app root, no forgetting to inject in test harnesses, no mismatched environments between previews and production.

The alternative — a value-type `DesignSystem` accessed through a `@MainActor` static — gives the same theming flexibility with none of the hidden-channel cost.

---

## 4. Token set inventory

Four token sets compose a `DesignSystem`:

| Token set | Purpose | Examples |
|---|---|---|
| `ColorTokens` | Adaptive named colors from the asset catalog | `.ink`, `.surface`, `.paper`, `.secondaryLabel`, `.tertiaryLabel`, `.separator`, `.accent` |
| `TypographyTokens` | Named font presets (system + custom) | `.largeTitle`, `.title2`, `.headline`, `.body`, `.subheadline`, `.footnote`, `.monoLabel` |
| `SpacingScale` | 4pt grid spacing values | `.xs` (4), `.sm` (8), `.md` (12), `.base` (16), `.lg` (24), `.xl` (32) |
| `LayoutTokens` | Fixed structural dimensions | `.hitTarget` (44), `.dialogWidth` (300), `.cardCornerRadius` (12), `.sheetCornerRadius` (20) |

Token sets are **flat and finite**. There are no nested token hierarchies (`colors.semantic.success.foreground.hover`), no token aliases (`colors.button.primary = colors.accent`), no token interpolation. A flat list of seven colors is easier to remember and easier to swap wholesale for a theme variant than a deeply nested hierarchy.

When a future theme needs a new conceptual color (e.g. `success`, `warning`), it is added to **`ColorTokens` directly** — every theme then provides a value for it. No special-case theming.

---

## 5. The `DesignSystem` value type

```swift
import SwiftUI

struct DesignSystem: Sendable {
    let colors: ColorTokens
    let typography: TypographyTokens
    let spacing: SpacingScale
    let layout: LayoutTokens

    static let standard = DesignSystem(
        colors: .standard,
        typography: .standard,
        spacing: .standard,
        layout: .standard
    )
}

struct ColorTokens: Sendable {
    let ink: Color
    let surface: Color
    let paper: Color
    let secondaryLabel: Color
    let tertiaryLabel: Color
    let separator: Color
    let accent: Color

    static let standard = ColorTokens(
        ink: Color("ink/Ink"),
        surface: Color("ink/Surface"),
        paper: Color("ink/Paper"),
        secondaryLabel: Color("ink/SecondaryLabel"),
        tertiaryLabel: Color("ink/TertiaryLabel"),
        separator: Color("ink/Separator"),
        accent: Color("ink/Accent")
    )
}

struct TypographyTokens: Sendable {
    let largeTitle: Font
    let title2: Font
    let headline: Font
    let body: Font
    let subheadline: Font
    let footnote: Font
    let monoLabel: Font

    static let standard = TypographyTokens(
        largeTitle: .custom("NewYork-Bold", size: 34, relativeTo: .largeTitle),
        title2: .custom("NewYork-Semibold", size: 22, relativeTo: .title2),
        headline: .custom("SFPro-Semibold", size: 17, relativeTo: .headline),
        body: .custom("SFPro-Regular", size: 17, relativeTo: .body),
        subheadline: .custom("SFPro-Regular", size: 15, relativeTo: .subheadline),
        footnote: .custom("SFPro-Regular", size: 13, relativeTo: .footnote),
        monoLabel: .custom("SFMono-Regular", size: 13, relativeTo: .footnote)
    )
}

struct SpacingScale: Sendable {
    let xs: CGFloat
    let sm: CGFloat
    let md: CGFloat
    let base: CGFloat
    let lg: CGFloat
    let xl: CGFloat

    static let standard = SpacingScale(xs: 4, sm: 8, md: 12, base: 16, lg: 24, xl: 32)
}

struct LayoutTokens: Sendable {
    let hitTarget: CGFloat
    let dialogWidth: CGFloat
    let cardCornerRadius: CGFloat
    let sheetCornerRadius: CGFloat

    static let standard = LayoutTokens(
        hitTarget: 44,
        dialogWidth: 300,
        cardCornerRadius: 12,
        sheetCornerRadius: 20
    )
}
```

All token-set types are `Sendable` value types. `DesignSystem` itself is `Sendable`. This matters for snapshot tests that may run on background queues and for any future async theme-loading code.

---

## 6. The injection seam — `current` and `withDesignSystem`

`Style` presets read tokens through `DesignSystem.current`, not directly from `ColorTokens.standard`. This is the seam:

```swift
extension DesignSystem {
    /// The active design system. v1 always returns `.standard`. Future versions
    /// may return a user-selected theme.
    @MainActor
    static private(set) var current: DesignSystem = .standard

    /// Replace the active design system. v1 calls this at most once at app
    /// startup. Future settings UI calls this when the user selects a theme.
    @MainActor
    static func use(_ system: DesignSystem) {
        current = system
    }

    /// Run a closure with a temporarily replaced design system. Used by snapshot
    /// tests and per-preview theme variants. Restores the previous value on return.
    @MainActor
    static func withDesignSystem<T>(
        _ system: DesignSystem,
        perform: () throws -> T
    ) rethrows -> T {
        let previous = current
        current = system
        defer { current = previous }
        return try perform()
    }
}
```

**Why `@MainActor`-isolated.** Theming changes affect rendering. SwiftUI rendering is main-thread-only. Constraining `current` to `@MainActor` prevents accidental cross-thread reads and matches the actor isolation of every consumer (`Style.standard`, `View.body`, snapshot tests using `MainActor.run`).

**Why `private(set)`.** External code can read `current` but only mutate via `use(_:)` or `withDesignSystem(_:perform:)`. This makes call sites greppable — there are exactly two ways to change the active design system, and both are named.

**Why `withDesignSystem` is `rethrows`.** Snapshot tests that throw assertion errors should propagate through the closure unchanged.

---

## 7. `Style.standard` is computed, not stored

This is the single most important detail in this EDD. Every `Style.standard` is a **`static var` computed property**, never a `static let` stored constant:

```swift
extension ActionCard.Style {
    @MainActor
    static var standard: Style {
        Style(
            titleFont: DesignSystem.current.typography.headline,
            titleColor: DesignSystem.current.colors.ink,
            subtitleFont: DesignSystem.current.typography.subheadline,
            subtitleColor: DesignSystem.current.colors.secondaryLabel,
            background: DesignSystem.current.colors.surface,
            spacing: DesignSystem.current.spacing.sm,
            padding: DesignSystem.current.spacing.base
        )
    }
}
```

A `static let` captures values at first access and never updates. A `static var` computed property reads `DesignSystem.current` on every access. Without the computed form, swapping the design system has **no effect** — existing `Style` values remain frozen at first-access time, and the bug is silent (no compile error, no runtime warning, just a view that ignores the theme switch).

The cost is rebuilding the `Style` struct on each read. For value types this small (a handful of `Color`, `Font`, and `CGFloat` fields), the cost is negligible. The read happens once per view-body invocation, not per frame.

**This rule is non-negotiable.** Enforcement: §16 below describes a SwiftLint custom rule to flag stored `static let` Style presets.

---

## 8. Asset catalog structure

All `Color` values referenced by `ColorTokens.standard` resolve from the asset catalog. The naming convention groups colors by theme prefix:

```
Assets.xcassets/
├── ink/
│   ├── Ink.colorset                  (light: #1A1A1A, dark: #F2F2F0)
│   ├── Surface.colorset              (light: #FAFAF8, dark: #1C1C1E)
│   ├── Paper.colorset                (light: #FFFFFF, dark: #000000)
│   ├── SecondaryLabel.colorset       (light: #6B6B6B, dark: #A0A0A0)
│   ├── TertiaryLabel.colorset        (light: #9B9B9B, dark: #6B6B6B)
│   ├── Separator.colorset            (light: #E0E0E0, dark: #2C2C2E)
│   └── Accent.colorset               (light: #2C2C2E, dark: #F2F2F0)
└── notebookCovers/                   (domain-specific colors, not theme tokens)
    ├── Slate.colorset
    ├── Sand.colorset
    ├── Sage.colorset
    └── Rose.colorset
```

**Convention:** the folder name (`ink/`) becomes the prefix in the `Color("ink/Ink")` lookup. This keeps the asset catalog navigable as token sets grow, and it makes the connection between a color name in code and its file in the catalog obvious.

**Domain colors live in their own folder.** `notebookCovers/` is not a `ColorTokens` set — those colors are content (a notebook's chosen cover color), not structural theme. They live in the asset catalog because they need light/dark variants and because asset catalogs are the right place for `Color` resources, but they are not part of `DesignSystem`.

When a high-contrast theme ships, it adds a parallel folder:

```
Assets.xcassets/
├── ink/                              (standard tokens)
└── inkHC/                            (high-contrast tokens)
    ├── Ink.colorset                  (higher contrast variants)
    └── ...
```

`ColorTokens.highContrast` references `Color("inkHC/Ink")`, etc. No name collisions, no shared assets, easy to diff.

---

## 9. Typography & font loading

Typography uses two custom font families plus the system font:

| Family | Use | Bundled |
|---|---|---|
| **New York** (`NewYork-Bold`, `NewYork-Semibold`) | Display titles, large headers — gives the app its editorial "ink on paper" feel | Yes (via `UIFontDescriptor.systemFont(ofSize:design:.serif)` on iOS 13+ — no font file shipping required) |
| **SF Pro** (`SFPro-Regular`, `SFPro-Semibold`) | Body, headline, subheadline, footnote — system default | System |
| **SF Mono** (`SFMono-Regular`) | Code labels, technical metadata, OCR confidence indicators | System |

**No third-party fonts in v1.** New York and SF families are Apple-supplied and need no bundling, licensing, or fallback handling.

`Font.custom(_:size:relativeTo:)` is used so all typography respects Dynamic Type. Setting `relativeTo:` ties the custom font to a system text style, and SwiftUI scales it with the user's accessibility text size.

If a future theme needs a different typeface (e.g. a "high-readability" theme with Atkinson Hyperlegible), it bundles the font file in the app bundle and constructs `TypographyTokens.highReadability` with `Font.custom("AtkinsonHyperlegible-Regular", size: 17, relativeTo: .body)`. The `Style.standard` pattern handles the rest.

---

## 10. Spacing & layout philosophy

### 10.1 Spacing — 4pt grid, six values

```
xs: 4    sm: 8    md: 12    base: 16    lg: 24    xl: 32
```

Six values is the smallest set that covers every observed spacing need without forcing approximations. We deliberately stop at 32 — anything larger is structural and belongs in `LayoutTokens`, not `SpacingScale`.

Rules of thumb:

| Spacing value | Use |
|---|---|
| `xs` (4) | Adjacent related elements (icon + label) |
| `sm` (8) | Inside a single visual unit (card padding, button internal spacing) |
| `md` (12) | Between related elements (form rows) |
| `base` (16) | Between distinct elements (card edges, container padding) |
| `lg` (24) | Between sections |
| `xl` (32) | Between major page regions |

If a layout calls for a value outside this set, the layout is wrong, not the scale. Do not add `.smPlus = 10` or `.between = 14` — find the structural reason for the in-between value and resolve it.

### 10.2 Layout — fixed structural dimensions

`LayoutTokens` holds dimensions that are **not** part of the spacing rhythm:

```
hitTarget: 44            (Apple HIG minimum touch target)
dialogWidth: 300         (modal sheet width on regular size class)
cardCornerRadius: 12     (notebook card, dispatch task card)
sheetCornerRadius: 20    (presented sheets)
```

These exist as named tokens because they appear in many places and changing them once should change them everywhere. Magic numbers like `cornerRadius: 12` scattered through component views fail this test.

---

## 11. What v1 ships vs. what the seam enables

| Capability | v1 status | How v2+ adds it |
|---|---|---|
| `DesignSystem.standard` exists | ✓ Ships | — |
| `DesignSystem.current` accessor | ✓ Ships, always `.standard` | No change — settings calls `use(_:)` |
| `Style.standard` reads from `current` | ✓ Ships | No change — picks up swap automatically |
| `withDesignSystem(_:perform:)` | ✓ Ships, used by tests | No change — additional snapshot coverage for new themes |
| Additional `DesignSystem` instances (`.highContrast`, custom user themes) | Not shipped | Add new `static let` instances on `DesignSystem` |
| Settings UI to select theme | Not shipped | New `SettingsFeature` action calls `DesignSystem.use(_:)` and persists choice to `UserPreferences` |
| Per-component `Style` presets (`.compact`, `.large`) | Add as needed | Already supported — same `static var` pattern |
| Mid-session theme switching | Not shipped | Top-level `.id(themeIdentifier)` modifier on the root scene OR app relaunch on theme change |

In v1, `DesignSystem.use(_:)` is **never called from production code**. `current` always returns `.standard`. The function exists so that when a settings screen ships, it has somewhere to write to.

`withDesignSystem(_:perform:)` *is* used in v1 — by snapshot tests, even though they will only ever swap `.standard` for `.standard`. Establishing the test pattern from day one means future theme variants ship with snapshot coverage automatically.

---

## 12. Adding a new theme later

When a high-contrast theme (or any other variant) ships, the work is:

**Step 1 — Add asset-catalog colors.**
Create `Assets.xcassets/inkHC/` with a `.colorset` for each `ColorTokens` field.

**Step 2 — Add the token-set instances.**

```swift
extension ColorTokens {
    static let highContrast = ColorTokens(
        ink: Color("inkHC/Ink"),
        surface: Color("inkHC/Surface"),
        paper: Color("inkHC/Paper"),
        secondaryLabel: Color("inkHC/SecondaryLabel"),
        tertiaryLabel: Color("inkHC/TertiaryLabel"),
        separator: Color("inkHC/Separator"),
        accent: Color("inkHC/Accent")
    )
}

extension DesignSystem {
    static let highContrast = DesignSystem(
        colors: .highContrast,
        typography: .standard,        // typography unchanged
        spacing: .standard,           // spacing unchanged
        layout: .standard             // layout unchanged
    )
}
```

**Step 3 — Wire the settings toggle.**

Add a field to `UserPreferences` (data layer EDD §5.9):

```swift
var themeIdentifier: String = "standard"   // "standard" | "highContrast"
```

In `AppFeature` reducer's `onLaunch`:

```swift
case .onLaunch:
    return .run { _ in
        let prefs = localModelContext().fetchPreferences()
        let theme: DesignSystem = prefs.themeIdentifier == "highContrast"
            ? .highContrast
            : .standard
        await MainActor.run {
            DesignSystem.use(theme)
        }
    }
```

In `SettingsFeature`:

```swift
case .themeChanged(let identifier):
    state.themeIdentifier = identifier
    return .run { _ in
        let prefs = localModelContext().fetchPreferences()
        prefs.themeIdentifier = identifier
        try localModelContext().save()
        // Theme takes effect on next launch (v2 behavior).
        // OR: trigger view-tree rebuild (v3 behavior).
    }
```

**Total surface touched:** one extension on `DesignSystem`, one extension on `ColorTokens`, one new asset-catalog folder, one persisted field, two reducer cases. Zero changes to component views. Zero changes to `Style` definitions.

---

## 13. Persistence of theme selection

Theme selection persists in `UserPreferences` (the **local-only** container — see data layer EDD §5.9 and §9). Theme is **per-device, not per-user**:

- A user might prefer high contrast on their iPhone (small screen, bright sunlight) and standard on their iPad (large screen, indoor reading).
- A high-contrast preference on a user's spare device shouldn't force the same on their primary device.
- Asset-catalog dark-mode variants already follow the OS appearance per-device.

Putting `themeIdentifier` in the synced container would cause cross-device theme drift the user did not ask for. The local-only container handles this correctly with no extra logic.

This decision is reversible — if telemetry shows users *do* expect theme to sync, the field migrates to the synced container with a one-time copy.

---

## 14. Snapshot tests for token coverage

Every component view ships a snapshot test that runs under `DesignSystem.standard`. When a second theme ships, the test gains a parallel case under that theme:

```swift
final class ActionCardSnapshotTests: XCTestCase {
    func testActionCard_standard() {
        DesignSystem.withDesignSystem(.standard) {
            assertSnapshot(
                of: ActionCardPreview(state: .populated),
                as: .image(layout: .device(config: .iPhone16))
            )
        }
    }

    // Added when high-contrast theme ships.
    // func testActionCard_highContrast() {
    //     DesignSystem.withDesignSystem(.highContrast) {
    //         assertSnapshot(
    //             of: ActionCardPreview(state: .populated),
    //             as: .image(layout: .device(config: .iPhone16))
    //         )
    //     }
    // }
}
```

**v1 always uses `withDesignSystem(.standard)` even though it's a no-op swap.** This establishes the pattern. When a second theme ships, adding coverage is one copy-pasted test. Without the wrapping, retrofitting theme tests later requires editing every snapshot test in the suite.

---

## 15. Dynamic Type & accessibility

### Dynamic Type

All `TypographyTokens` use `Font.custom(_:size:relativeTo:)` with a `relativeTo:` system text style. SwiftUI scales custom fonts proportionally to Dynamic Type settings without further work.

Snapshot tests at the largest accessibility size (`accessibility5`) verify layouts don't break:

```swift
func testActionCard_largestText() {
    assertSnapshot(
        of: ActionCardPreview(state: .populated)
            .environment(\.dynamicTypeSize, .accessibility5),
        as: .image(layout: .device(config: .iPhone16))
    )
}
```

This is the **one** acceptable use of `@Environment` injection in a snapshot test — `dynamicTypeSize` is an OS-level concern, not a design-token concern.

### Reduce Motion, Reduce Transparency

These OS settings are read via `@Environment` *inside view bodies* only when a specific component genuinely needs them (a animated component checking `accessibilityReduceMotion`). They are **not** wired into `DesignSystem` — they are not theme tokens.

### High-contrast OS setting

iOS exposes `UIAccessibility.isDarkerSystemColorsEnabled` and the `accessibilityContrast` environment value. v2+ may auto-switch to a high-contrast `DesignSystem` when this is on. v1 ignores it; users on the OS high-contrast setting get the standard theme with whatever contrast the asset catalog provides.

---

## 16. Known footguns & enforcement

### Footgun 1 — `static let standard` instead of `static var standard`

A stored static caches the value at first access. The bug is silent: no compile error, no runtime warning, just a view that doesn't react to theme changes. The mistake is *very* easy to make because `static let` is the more idiomatic Swift form for constants.

**Enforcement:** SwiftLint custom rule, added in F-04:

```yaml
custom_rules:
  static_let_style_preset:
    name: "Style preset must be static var, not static let"
    regex: 'static\s+let\s+\w+\s*=\s*Style\('
    match_kinds:
      - identifier
    message: "Style presets must be `static var` computed properties, not `static let` stored constants. See Design System EDD §7."
    severity: error
```

The regex is approximate but catches the common case. The error message points to this EDD.

### Footgun 2 — Reading `DesignSystem.current` inside a view body

This works mechanically — the view rebuilds and re-reads `current` on the next render. But it bypasses the `Style` layer, scatters direct token reads through view bodies, and breaks the rule that views are pure functions of their `Model`.

**Enforcement:** code review. No automated rule — too easy to false-positive (e.g. `DesignSystem.current` inside a `static var standard` body is correct). Worth a once-per-PR grep: `git diff | grep 'DesignSystem.current' | grep -v 'static var'`.

### Footgun 3 — Adding a new color to one theme but not others

When `ColorTokens.highContrast` ships, both standard and high-contrast must define every field. Swift's struct memberwise init enforces this — adding a field to `ColorTokens` forces every static instance to compile-error until updated. This is *the* mechanism that prevents themes from drifting; do not abandon it by giving fields default values.

**Enforcement:** the type system. Do not add default values to `ColorTokens` fields.

---

## 17. Anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| `@Environment(\.designSystem)` | Reintroduces hidden input channel | Read `DesignSystem.current` inside `Style.standard` only |
| `static let standard = Style(...)` for a Style preset | Theme swaps silently fail | `static var standard: Style { Style(...) }` |
| Reading `DesignSystem.current` inside a view body | Bypasses the `Style` abstraction | Build a `Style` preset and read `model.style.*` |
| Magic numbers in views (`spacing: 14`, `cornerRadius: 8`) | Disconnects layout from token system | Reference `model.style.*` or pull into `LayoutTokens` |
| Adding mid-scale spacing values (`smPlus: 10`) | Bloats the scale, encourages "in-between" thinking | Find the structural reason; redesign the layout |
| Domain colors in `ColorTokens` (`notebookCoverSlate`) | Mixes content with theme | Domain colors live in their own asset folder, referenced as `Color` directly |
| Default values on `ColorTokens` fields | Defeats compile-time theme-completeness check | All `ColorTokens` fields are non-optional, no defaults |
| Per-platform `DesignSystem.iOS` and `.macOS` | Forks the system unnecessarily | One `DesignSystem`; `LayoutTokens` accommodates platform differences if needed |

---

## 18. Open questions

1. **Notebook cover colors as a domain palette.** Should `notebookCovers/` colors be exposed as a typed enum (`NotebookCover.slate`, `.sand`, `.sage`, `.rose`) or as raw asset names? **Default: typed enum**, lives in the Library feature, not the design system.
2. **Typography for the canvas (handwritten ink).** The canvas does not render text — ink is bitmap data. But OCR results and dispatch tasks may quote handwritten text alongside extracted typed text; should there be a `.handwritingExcerpt` font preset (italic SF Pro)? **Default: defer until the dispatch UI is built; add to `TypographyTokens` only if a real second use emerges.**
3. **`accessibilityContrast` auto-detection in v2.** When the high-contrast theme ships, should the app auto-switch when the OS contrast setting is on, or require explicit user opt-in? **Default: opt-in via Settings**, with a hint when the OS setting is detected.
4. **Theme preview in Settings.** When themes ship, should the settings screen render a live preview of the theme before applying? Adds complexity but is a strong UX. **Default: defer; ship theme switch first, preview later.**

---

## 19. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-08 | Design system accessed through `DesignSystem.current`, not `@Environment`. | Keeps views as pure functions of `Model + Style` while preserving the option to add theming later. |
| 2026-05-08 | `Style.standard` is `static var` computed, not `static let` stored. | Required so future `DesignSystem.use(_:)` calls take effect without per-component refactor. |
| 2026-05-08 | `DesignSystem.use(_:)` ships unused in v1; `withDesignSystem` ships used by tests. | Building the seam without the feature; ensures future themes ship with snapshot coverage by default. |
| 2026-05-08 | Token sets are flat, finite, and have no defaults. | Compile-time enforcement that every theme defines every token; encourages discipline over expansion. |
| 2026-05-08 | Theme persistence will live in `UserPreferences` (local-only container) when shipped. | Theme is per-device, not per-user; matches the existing local-only sync boundary. |
| 2026-05-08 | Asset catalog uses theme-prefixed folders (`ink/`, future `inkHC/`). | Easy navigation as themes grow; no name collisions; trivial diffing. |
| 2026-05-08 | Spacing scale stops at six values (`xs` to `xl`). | Forces structural thinking; "in-between" values indicate layout problems. |
| 2026-05-08 | Custom fonts limited to system-supplied (New York, SF Pro, SF Mono). | No bundle weight, no licensing, no fallback handling. |
| 2026-05-08 | Mid-session theme changes not supported in v1. | Would require app-wide view-tree rebuild; theme switch on relaunch is sufficient for v2 launch. |
| 2026-05-08 | `dynamicTypeSize` is the one acceptable `@Environment` injection in snapshot tests. | OS-level accessibility setting, not a design-system concern. |