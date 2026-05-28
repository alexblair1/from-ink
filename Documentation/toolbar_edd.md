# EDD — Toolbar System

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-27 |
| Implements ticket | F-07 (NotebookFeature) |
| Companion docs | EDD — View Layer, EDD — Data Layer |

---

## Table of contents

1. [Summary](#1-summary)
2. [Goals & non-goals](#2-goals--non-goals)
3. [Architecture](#3-architecture)
4. [ToolbarFeature reducer](#4-toolbarfeature-reducer)
5. [Supporting types](#5-supporting-types)
6. [Tool descriptors](#6-tool-descriptors)
7. [Toolbar zones](#7-toolbar-zones)
8. [View layer](#8-view-layer)
9. [Panel presentation](#9-panel-presentation)
10. [Gestures & imperative boundaries](#10-gestures--imperative-boundaries)
11. [Settings persistence](#11-settings-persistence)
12. [Integration with NotebookFeature](#12-integration-with-notebookfeature)
13. [Testing](#13-testing)
14. [Open questions](#14-open-questions)
15. [Decision log](#15-decision-log)

---

## 1. Summary

The toolbar is a TCA child feature scoped under `NotebookFeature` (the toolbar is notebook-wide chrome that lives outside the paged `TabView` — see §3.2 for the render-site invariant). It manages tool selection, per-tool settings, panel presentation, and toolbar side. The view layer follows the three-tier taxonomy: component views for buttons and panels, a feature view for layout, and a wiring view for Store binding. Apple Pencil gestures (double-tap, squeeze, two-finger hold) and drag-to-switch-sides flow through the reducer as discrete actions — they do not bypass TCA.

---

## 2. Goals & non-goals

### Goals

- Every tool selection, gesture, and panel toggle is a `TestStore`-verifiable state transition.
- Adding a new tool requires creating a descriptor and appending it to a zone array. No switch statements elsewhere.
- Per-tool settings (pen type, thickness, graphite grade, highlighter color) persist across app launches.
- The toolbar view is snapshot-testable without a Store.

### Non-goals

- This EDD does not cover drawing data, stroke persistence, or OCR — those are `CanvasFeature` concerns (View Layer EDD §10).
- This EDD does not cover the lasso action menu (`LassoMenuBar`) — that is a separate component triggered by lasso completion, not a toolbar concern.
- This EDD does not cover the bolt/analysis button — that is a `CanvasFeature` concern driven by stroke count.

---

## 3. Architecture

```
NotebookFeature (Reducer — manual conformance, see §3.1)
  └─ Scope(state: \.toolbar, action: \.toolbar)
       └─ ToolbarFeature (Reducer)
            ├─ State: activeToolID, toolStack, toolSettings, openPanel, side,
            │         isBoltVisible, isDispatchRequested, customizingSettings
            ├─ Action: toolTapped, pencilDoubleTapped, twoFingerHoldBegan, …
            └─ Dependencies: @Dependency(\.userPreferences)

NotebookScreen (wiring tier — sibling to TabView)
  ├─ TabView(.page) { CanvasScreen(…, toolbarStore: …) per page }
  └─ ToolbarWiringView (single instance, scoped store)
       └─ ToolbarView (feature view, no TCA)
            ├─ ToolButtonView (component)
            ├─ ActionButtonView (component)
            └─ DragHandleView (component)
```

**Layer mapping per View Layer EDD §4:**

| View | Tier | Imports TCA | Accepts |
|---|---|---|---|
| `ToolButtonView` | Component | No | `let model: Model` |
| `ActionButtonView` | Component | No | `let model: Model` |
| `DragHandleView` | Component | No | `let model: Model` |
| `ToolbarView` | Feature | No | `let model: Model` |
| `ToolbarWiringView` | Wiring | Yes | `StoreOf<ToolbarFeature>` |

### 3.1 Manual `Reducer` conformance — no `@Reducer` macro

This project is built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The `@Reducer` macro resolves `ReducerOf<Self>` during expansion, which creates a circular reference under that build setting that the compiler cannot resolve. Every reducer in this project — `ToolbarFeature` included — uses manual conformance:

```swift
struct ToolbarFeature: Reducer {
    @ObservableState struct State: Equatable { … }
    @CasePathable enum Action: Equatable { … }
    var body: some Reducer<State, Action> {
        Reduce { state, action in … }
    }
}
```

`Action: Equatable` is mandatory because the parent (`NotebookFeature.Action`) is `Equatable` and the macro-generated synthesis can't deduce it for non-`Equatable` payloads.

### 3.2 Render-site invariant — toolbar lives at NotebookScreen level

`ToolbarWiringView` MUST be rendered as a sibling of `NotebookScreen`'s `TabView(.page)` — never inside `CanvasScreen` or any per-page view. The reasons are non-negotiable:

1. **Page swipes must not translate the toolbar.** When a view is rendered inside a paged `TabView`, it is mounted per-page and translates with the swipe gesture. The toolbar is canvas chrome, not page content; it has to stand still.
2. **Tool selection persists across pages.** A single `ToolbarFeature` store backs the rail; per-page stores would mean a tool change on page 3 is invisible on page 4.
3. **N instances → 1 instance.** A per-page render creates a fresh `ToolbarWiringView` for every visible + preloaded page; lifting reduces to one.

**Hard rule for code review:** `grep -R "ToolbarWiringView" FromInk/Canvas/` must return zero results. If the toolbar appears inside a per-page view, the change is wrong.

**Overlays — pinned vs per-page audit:**

| Overlay | Lifecycle | Render site |
|---|---|---|
| `ToolbarWiringView` | Notebook-wide; persists across page swipes | `NotebookScreen` |
| Toolbar panel (`openPanel`) | Notebook-wide; persists across swipes | `NotebookScreen` |
| Dismiss / close X | Notebook-wide; persists across swipes | `NotebookScreen` |
| Page navigator (prev/next pill) | Notebook-wide | `NotebookScreen` |
| Add-page button | Notebook-wide | `NotebookScreen` |
| Universal Dispatch modal | Notebook-wide for the active task; cancelled on page swipe by design | `CanvasScreen` (per-page state for v1; transient overlay) |
| Lasso menu / lasso preview | Page-specific; tied to the active page's drawing | `CanvasScreen` |
| Header indicators / link indicators | Page-specific; bound to per-page state | `CanvasScreen` |
| Dispatch side panel (regular size class) | Per-page (headers/links are per-page) | `CanvasScreen` |

If a new overlay's lifecycle is notebook-wide, it goes in `NotebookScreen`. If it's page-specific, it stays in `CanvasScreen`. The wrong placement is observable as either a UI element swiping with the page (when it shouldn't) or per-page UI duplicating across pages.

---

## 4. ToolbarFeature reducer

`ToolbarFeature.swift` is the source of truth; this section sketches the State + Action shape and the load-bearing semantic choices that aren't obvious from the type signatures alone.

```swift
struct ToolbarFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var activeToolID: ToolID = .pen
        /// Pre-resolved per-tool settings for the active tool. Mirrors
        /// `toolSettings[id: activeToolID]?.settings` but stored, not
        /// computed — see "State holds resolved values" in CLAUDE.md.
        var activeSettings: PenSettings = .default

        /// Restoration stack for transient tool switches. Pushed on
        /// pencil double-tap (→ eraser) and two-finger hold (→ lasso);
        /// popped to restore. Multi-level so a hold-during-eraser nests
        /// correctly: pen → eraser → lasso → eraser → pen.
        var toolStack: [ToolID] = []

        /// Per-tool persisted settings (thickness, penType, etc.).
        var toolSettings: IdentifiedArrayOf<ToolSettingsEntry> = []

        var openPanel: PanelKind? = nil
        var side: ToolbarSide = .left

        /// Set explicitly by the canvas when stroke count crosses 10.
        /// Stored, not computed from a strokeCount field — the toolbar
        /// only cares about the boolean, so it stores only the boolean.
        var isBoltVisible: Bool = false

        /// Forwarded-to-parent flag for the compact-size-class dispatch
        /// button. Parent observes, presents the dispatch panel, then
        /// sends `.dispatchAcknowledged` to reset.
        var isDispatchRequested: Bool = false

        /// Pre-resolved settings for the currently open customization
        /// panel. Reducer sets this when `.toolTapped` opens the panel
        /// (and on `.toolSettingsChanged` when the panel is active). The
        /// view's binding reads it directly — no `?? .default` fallback.
        /// See §9.1 for the contract.
        var customizingSettings: PenSettings = .default
    }

    @CasePathable
    enum Action: Equatable {
        // Tool interaction — one action per user intent. The reducer
        // disambiguates "switch tool" vs "toggle the panel for the
        // already-active tool" internally.
        case toolTapped(ToolID)

        // Apple Pencil gestures (sent from CanvasView.Coordinator).
        case pencilDoubleTapped
        case pencilSqueezed
        case twoFingerHoldBegan
        case twoFingerHoldEnded

        // Per-tool settings persistence.
        case toolSettingsChanged(ToolID, PenSettings)

        // Panels.
        case templatePickerToggled
        case settingsToggled
        case panelDismissed

        // Chrome.
        case sideChanged(ToolbarSide)
        case boltVisibilityChanged(Bool)

        // Forwarded to parent — return .none here.
        case undoTapped
        case redoTapped
        case analyzeTapped
        case dispatchTapped
        case dispatchAcknowledged
        case templateSelected(CanvasTemplate)

        // Lifecycle.
        case onAppear
        case settingsLoaded(LoadedSettings)
    }

    @Dependency(\.userPreferences) var preferences

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            // Switch tool: clear the restoration stack — a deliberate
            // tool change is the user committing, not a transient.
            case .toolTapped(let id) where id != state.activeToolID:
                state.toolStack = []
                state.activeToolID = id
                state.activeSettings = state.toolSettings[id: id]?.settings ?? .default
                state.openPanel = nil
                return .none

            // Tap on the already-active tool — toggle its customization
            // panel if the tool supports customization. Also pre-resolve
            // `customizingSettings` so the view binding has no fallback.
            case .toolTapped(let id):
                let canCustomize = ToolDescriptor.descriptor(for: id)?.hasCustomization ?? false
                guard canCustomize else { return .none }
                let willOpen = state.openPanel != .toolCustomization(id)
                state.openPanel = willOpen ? .toolCustomization(id) : nil
                if willOpen {
                    state.customizingSettings = state.toolSettings[id: id]?.settings ?? .default
                }
                return .none

            // … remaining cases follow the same single-source-of-truth
            // pattern: state mutations resolve to stored values; effects
            // only persist via UserPreferences. See ToolbarFeature.swift.

            // …

            }
        }
    }
}
```

**Why the State shape is "resolved values, not computed":** earlier iterations had `activeSettings` computed as `toolSettings[id: activeToolID]?.settings ?? .default`. That works but bakes a fallback into a derived getter — which then leaks into bindings on the view side. Storing `activeSettings` as a plain property, mutated explicitly on every action that affects it, keeps the fallback in exactly one place (the reducer) and makes the view's read site dumb. Same logic for `isBoltVisible` (boolean, not `strokeCount >= 10`) and `customizingSettings`.

**Equatable on Action is required.** `NotebookFeature.Action: Equatable` includes `.toolbar(ToolbarFeature.Action)`, so the child action must conform. All payload types — `ToolID`, `PenSettings`, `ToolbarSide`, `CanvasTemplate`, `LoadedSettings`, `PanelKind` — are also `Equatable`.

---

## 5. Supporting types

### ToolID

```swift
struct ToolID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: String

    static let pen = ToolID(rawValue: "pen")
    static let fountain = ToolID(rawValue: "fountain")
    static let pencil = ToolID(rawValue: "pencil")
    static let marker = ToolID(rawValue: "marker")
    static let highlighter = ToolID(rawValue: "highlighter")
    static let eraser = ToolID(rawValue: "eraser")
    static let lasso = ToolID(rawValue: "lasso")
}
```

**Why a struct, not an enum.** Adding a tool does not require modifying the type — add a new static constant. Enum cases force exhaustive switches everywhere a tool is matched, creating coupling between unrelated code paths.

### ToolSettingsEntry

```swift
struct ToolSettingsEntry: Identifiable, Equatable, Codable, Sendable {
    let id: ToolID
    var settings: PenSettings
}
```

### PanelKind

```swift
enum PanelKind: Equatable {
    case toolCustomization(ToolID)
    case templatePicker
    case canvasSettings
}
```

### ToolbarSide

```swift
enum ToolbarSide: String, Equatable, Codable, Sendable {
    case left, right
}
```

---

## 6. Tool descriptors

A tool descriptor declares identity, icon, label, and PencilKit mapping. The toolbar view does not know what a tool does — it renders an icon and forwards taps.

```swift
struct ToolDescriptor: Equatable, Sendable {
    let id: ToolID
    let icon: String
    let label: String
    let hasCustomization: Bool
    let makePKTool: @Sendable (PenSettings) -> PKTool
}
```

> **Note:** `makePKTool` is not `Equatable`. `ToolDescriptor` conforms to `Equatable` by comparing `id` only (sufficient because IDs are unique).

### Built-in descriptors

```swift
extension ToolDescriptor {
    static let pen = ToolDescriptor(
        id: .pen, icon: "pencil", label: "Pen",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let fountain = ToolDescriptor(
        id: .fountain, icon: "pencil.tip", label: "Fountain",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let pencil = ToolDescriptor(
        id: .pencil, icon: "scribble", label: "Pencil",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let marker = ToolDescriptor(
        id: .marker, icon: "paintbrush.pointed", label: "Marker",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let highlighter = ToolDescriptor(
        id: .highlighter, icon: "highlighter", label: "Highlighter",
        hasCustomization: true,
        makePKTool: { $0.pkTool }
    )

    static let eraser = ToolDescriptor(
        id: .eraser, icon: "eraser", label: "Eraser",
        hasCustomization: false,
        makePKTool: { _ in PKEraserTool(.bitmap) }
    )

    static let lasso = ToolDescriptor(
        id: .lasso, icon: "lasso", label: "Lasso",
        hasCustomization: false,
        makePKTool: { _ in PKLassoTool() }
    )

    /// The ordered set of all writing tools. Toolbar renders from this array.
    static let allWritingTools: [ToolDescriptor] = [
        .pen, .fountain, .pencil, .marker, .highlighter, .eraser, .lasso
    ]
}
```

**Adding a new tool:** Create a new `ToolDescriptor` static constant, append it to `allWritingTools`. No switch statements, no other files touched.

---

## 7. Toolbar zones

The toolbar is a vertical stack of zones, separated by hairline rules. Each zone is an array of items. Zones are data, not hardcoded layout.

```swift
struct ToolbarZoneConfig: Equatable, Sendable {
    let id: String
    let items: [ToolbarZoneItem]
}

enum ToolbarZoneItem: Equatable, Sendable {
    case tool(ToolDescriptor)
    case action(id: String, icon: String)
    case bolt
    case dragHandle
}
```

### Default configuration

```swift
extension ToolbarZoneConfig {
    static func standard() -> [ToolbarZoneConfig] {
        [
            ToolbarZoneConfig(id: "handle", items: [.dragHandle]),
            ToolbarZoneConfig(id: "bolt", items: [.bolt]),
            ToolbarZoneConfig(id: "writing", items:
                ToolDescriptor.allWritingTools.map { .tool($0) }
            ),
            ToolbarZoneConfig(id: "actions", items: [
                .action(id: "undo", icon: "arrow.uturn.backward"),
                .action(id: "redo", icon: "arrow.uturn.forward"),
                .action(id: "template", icon: "square.grid.3x3"),
                .action(id: "settings", icon: "gearshape"),
            ]),
        ]
    }
}
```

---

## 8. View layer

### 8.1 Component views

**ToolButtonView** — a single tool icon in the toolbar rail.

```swift
struct ToolButtonView: View {
    let model: Model

    var body: some View {
        Button {
            model.onTap()
        } label: {
            Image(systemName: model.icon)
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.isActive ? model.style.activeForeground : model.style.inactiveForeground)
                .frame(width: model.style.width, height: model.style.height)
                .background(model.isActive ? model.style.activeBackground : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) { model.onDoubleTap() }
    }
}

extension ToolButtonView {
    struct Style {
        let width: CGFloat
        let height: CGFloat
        let activeForeground: Color
        let inactiveForeground: Color
        let activeBackground: Color

        static let standard = Style(
            width: LayoutTokens.standard.toolbarWidth,
            height: LayoutTokens.standard.toolbarButtonHeight,
            activeForeground: ColorTokens.standard.paperOnInk,
            inactiveForeground: ColorTokens.standard.ink2,
            activeBackground: ColorTokens.standard.ink
        )
    }

    struct Model {
        let icon: String
        let isActive: Bool
        let onTap: () -> Void
        let onDoubleTap: () -> Void
        let style: Style

        init(
            icon: String,
            isActive: Bool,
            onTap: @escaping () -> Void,
            onDoubleTap: @escaping () -> Void = {},
            style: Style = .standard
        ) {
            self.icon = icon
            self.isActive = isActive
            self.onTap = onTap
            self.onDoubleTap = onDoubleTap
            self.style = style
        }
    }
}
```

**ActionButtonView** — undo, redo, template, settings.

```swift
struct ActionButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Image(systemName: model.icon)
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.style.foreground)
                .frame(width: model.style.width, height: model.style.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ActionButtonView {
    struct Style {
        let width: CGFloat
        let height: CGFloat
        let foreground: Color

        static let standard = Style(
            width: LayoutTokens.standard.toolbarWidth,
            height: LayoutTokens.standard.toolbarButtonHeight,
            foreground: ColorTokens.standard.ink2
        )
    }

    struct Model {
        let icon: String
        let onTap: () -> Void
        let style: Style

        init(icon: String, onTap: @escaping () -> Void, style: Style = .standard) {
            self.icon = icon
            self.onTap = onTap
            self.style = style
        }
    }
}
```

### 8.2 Feature view — pinned-top / scrollable-middle / pinned-bottom

`ToolbarView` stretches edge-to-edge vertically and lays out zones in three regions:

- **Pinned top** — `placement == .pinnedTop` zones (currently: drag handle). Hugs the top edge.
- **Scrollable middle** — `placement == .flexible` zones (currently: bolt, writing tools). Wrapped in a `ScrollView` so the writing-tools zone stays reachable even when the rail's natural height exceeds the screen. `.scrollBounceBehavior(.basedOnSize)` suppresses rubber-banding on tall iPads where everything fits.
- **Pinned bottom** — `placement == .pinnedBottom` zones (currently: undo, redo, template, settings, optional dispatch on compact). Hugs the bottom edge.

Hairlines separate the three regions only when both sides have content. Within each region, the existing per-zone hairlines still apply.

```swift
import SwiftUI

struct ToolbarView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            zonesGroup(model.pinnedTopZones)
            if model.showsTopBoundaryRule { HairlineRule() }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    zonesGroup(model.flexibleZones)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if model.showsBottomBoundaryRule { HairlineRule() }
            zonesGroup(model.pinnedBottomZones)
        }
        .frame(width: model.width)
        .frame(maxHeight: .infinity)   // edge-to-edge anchor
        .background(model.background)
        .overlay(alignment: model.borderAlignment) {
            Rectangle()
                .fill(model.borderColor)
                .frame(width: model.borderWidth)
        }
    }

    @ViewBuilder
    private func zonesGroup(_ zones: [Model.Zone]) -> some View { … }
}

extension ToolbarView {
    struct Model {
        let pinnedTopZones: [Zone]
        let flexibleZones: [Zone]
        let pinnedBottomZones: [Zone]
        let showsTopBoundaryRule: Bool
        let showsBottomBoundaryRule: Bool
        let borderAlignment: Alignment
        let width: CGFloat
        let background: Color
        let borderColor: Color
        let borderWidth: CGFloat

        struct Zone: Identifiable {
            let id: String
            let items: [Item]
        }

        enum Item: Identifiable {
            case toolButton(ToolButtonView.Model)
            case actionButton(ActionButtonView.Model)
            case dragHandle(DragHandleView.Model)
        }
    }
}
```

The adapter (`ToolbarWiringView`) is responsible for bucketing zones by their `ToolbarZoneConfig.Placement` into the three model fields. The view itself never sees the placement enum — it just renders three lists.

**Why this geometry:** the writing-tools zone has 7 items at 54pt each, plus drag handle + bolt + 4 action buttons. The natural rail height is ~700pt — fits on iPad, overflows on iPhone (~667pt usable). The pinned regions guarantee the drag handle stays reachable for side switching and the actions stay reachable for save/template/undo, regardless of how tall the tools list grows. On tall screens nothing scrolls; the layout collapses cleanly.

### 8.3 Wiring view + adapter

```swift
import SwiftUI
import ComposableArchitecture

struct ToolbarWiringView: View {
    let store: StoreOf<ToolbarFeature>
    let zones: [ToolbarZoneConfig]
    let undoManager: UndoManager?

    var body: some View {
        ToolbarView(model: Self.makeModel(store: store, zones: zones, undoManager: undoManager))
    }

    private static func makeModel(
        store: StoreOf<ToolbarFeature>,
        zones: [ToolbarZoneConfig],
        undoManager: UndoManager?
    ) -> ToolbarView.Model {
        let viewZones = zones.map { zone in
            ToolbarView.Model.Zone(
                id: zone.id,
                items: zone.items.compactMap { item in
                    switch item {
                    case .tool(let descriptor):
                        return .toolButton(ToolButtonView.Model(
                            icon: store.toolSettings[id: descriptor.id]?.settings.penType.icon ?? descriptor.icon,
                            isActive: store.activeToolID == descriptor.id,
                            onTap: {
                                if store.activeToolID == descriptor.id {
                                    store.send(.toolDoubleTapped(descriptor.id))
                                } else {
                                    store.send(.toolSelected(descriptor.id))
                                }
                            },
                            onDoubleTap: { store.send(.toolDoubleTapped(descriptor.id)) }
                        ))

                    case .action(let id, let icon):
                        return .actionButton(ActionButtonView.Model(
                            icon: icon,
                            onTap: {
                                switch id {
                                case "undo": store.send(.undoTapped)
                                case "redo": store.send(.redoTapped)
                                case "template": store.send(.panelToggled(.templatePicker))
                                case "settings": store.send(.panelToggled(.canvasSettings))
                                default: break
                                }
                            }
                        ))

                    case .bolt:
                        guard store.isBoltVisible else { return nil }
                        return .bolt(BoltButton.Model(
                            isReady: store.isBoltVisible,
                            onTap: { store.send(.analyzeTapped) }
                        ))

                    case .dragHandle:
                        return .dragHandle(DragHandleView.Model(
                            onDragEnded: { side in store.send(.sideChanged(side)) }
                        ))
                    }
                }
            )
        }

        return ToolbarView.Model(zones: viewZones, side: store.side)
    }
}
```

**Key:** All TCA action dispatch happens in the adapter. `ToolbarView` and its component views have no knowledge of TCA, `Store`, or `Action` enums. They receive closures.

### 8.4 File structure

```
Features/Canvas/
  CanvasFeature.swift
  Toolbar/
    ToolbarFeature.swift           # Reducer (manual conformance, see §3.1)
    ToolDescriptor.swift           # ToolDescriptor + ToolID + allWritingTools
    ToolbarZoneConfig.swift        # Zone configuration types
    Views/
      ToolbarView.swift            # Feature view (no TCA)
      ToolbarWiringView.swift      # Wiring view + adapter
    Components/
      ToolButtonView.swift         # Component: tool icon button
      ActionButtonView.swift       # Component: action icon button
      DragHandleView.swift         # Component: drag handle
    Panels/
      PenCustomizationPanel.swift  # Component: pen settings panel
      TemplatePickerPanel.swift    # Component: template selection panel
      CanvasSettingsPanel.swift    # Component: canvas settings panel
    Previews/
      ToolbarViewPreview.swift     # FeaturePreview conformance
```

---

## 9. Panel presentation

Panels are presented by `NotebookScreen` (the toolbar's render site — see §3.2) based on `ToolbarFeature.State.openPanel`. They are component views with Model + Style — no TCA imports.

**PenCustomizationPanel** receives a `Binding<PenSettings>` (per View Layer EDD §9 — bindings passed alongside Model, not embedded in it):

```swift
struct PenCustomizationPanel: View {
    let model: Model
    @Binding var settings: PenSettings
    // ... pen type list, thickness selector, graphite/highlighter options
}
```

The wiring view reads `store.toolbar.openPanel` and presents the appropriate panel:

```swift
// In NotebookScreen
if let panel = store.toolbar.openPanel {
    switch panel {
    case .toolCustomization(let toolID):
        PenCustomizationPanel(
            model: .init(toolLabel: descriptor(for: toolID).label,
                         onDismiss: { toolbarStore.send(.panelDismissed) }),
            settings: Binding(
                get: { store.toolbar.customizingSettings },
                set: { toolbarStore.send(.toolSettingsChanged(toolID, $0)) }
            )
        )
    case .templatePicker:  TemplatePickerPanel(…)
    case .canvasSettings:  CanvasSettingsPanel(…)
    }
}
```

### 9.1 No defaulted bindings in views

The binding's `get` reads `store.toolbar.customizingSettings` directly. It does **not** look up `toolSettings[id: toolID]?.settings ?? .default` — that fallback was a previous shape of this code and is banned. Reason: `?? .default` expresses "what's the default for an unsaved tool" in the view, which is a reducer responsibility. The view is the wrong place for that knowledge — it leaks domain semantics into a binding closure where they're invisible to tests.

The replacement contract: `ToolbarFeature.State` carries `customizingSettings: PenSettings`. The reducer pre-populates it whenever `.toolTapped` opens a customization panel:

```swift
case .toolTapped(let id):
    let canCustomize = ToolDescriptor.descriptor(for: id)?.hasCustomization ?? false
    guard canCustomize else { return .none }
    let willOpen = state.openPanel != .toolCustomization(id)
    state.openPanel = willOpen ? .toolCustomization(id) : nil
    if willOpen {
        state.customizingSettings = state.toolSettings[id: id]?.settings ?? .default
    }
    return .none
```

And mirrors edits back into it when the active panel's settings change:

```swift
case .toolSettingsChanged(let id, let settings):
    state.toolSettings[id: id] = ToolSettingsEntry(id: id, settings: settings)
    if id == state.activeToolID {
        state.activeSettings = settings
    }
    if state.openPanel == .toolCustomization(id) {
        state.customizingSettings = settings
    }
    return .run { _ in await preferences.saveToolSettings(id, settings) }
```

The `?? .default` defaulting lives exactly once, inside the reducer, where state ownership belongs. The view's binding has no fallback because the reducer guarantees `customizingSettings` is meaningful whenever the panel is open.

### 9.2 v1 panel anchor trade-off

With the scrollable middle region (§8.2), the active writing-tool button can be scrolled off-screen. A "panel anchored to the active tool's frame" would chase a moving target.

For v1 the panel is **vertically centered** on the screen regardless of where the active tool button currently sits in the scroll region. Trade-off: the panel doesn't visually point at the active tool. Gain: the panel never disappears or jumps when the tool list scrolls, and the implementation has zero scroll-offset bookkeeping. Revisit if user feedback indicates the disconnect is confusing.

---

## 10. Gestures & imperative boundaries

Per View Layer EDD §10, Apple Pencil double-tap and squeeze are UIKit-level events. They arrive via `UIPencilInteraction` delegate in the `CanvasWrapper.Coordinator` and are forwarded as discrete TCA actions — not high-frequency, so they pass through the reducer.

```swift
// In CanvasWrapper.Coordinator
func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    store.send(.toolbar(.pencilDoubleTapped))
}

// Two-finger hold via UILongPressGestureRecognizer
func handleTwoFingerHold(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:  store.send(.toolbar(.twoFingerHoldBegan))
    case .ended, .cancelled: store.send(.toolbar(.twoFingerHoldEnded))
    default: break
    }
}
```

**Drag-to-switch-sides** is a SwiftUI `DragGesture` on `DragHandleView`. The gesture state (`isPressed`, `offset`) is `@GestureState` on the feature view (UI-local concern per View Layer EDD §17.1). On end, it calls the `onDragEnded` closure which the adapter maps to `.sideChanged(side)`.

---

## 11. Settings persistence

Per Data Layer EDD §4.9, `UserPreferences` is a local-only SwiftData model (never synced). The toolbar adds:

```swift
@Model final class UserPreferences {
    // ... existing fields (handedness, toolbarSide, fingerDrawingEnabled, lastOpenedNotebookID)

    var toolSettingsData: Data?       // JSON-encoded IdentifiedArrayOf<ToolSettingsEntry>
    var activeToolIDRaw: String = "pen"
    var templateNameRaw: String = "none"
}
```

### UserPreferences dependency

```swift
struct UserPreferencesDependency: Sendable {
    var loadToolSettings: @Sendable () async -> IdentifiedArrayOf<ToolSettingsEntry>
    var saveToolSettings: @Sendable (ToolID, PenSettings) async -> Void
    var loadToolbarSide: @Sendable () async -> ToolbarSide
    var saveToolbarSide: @Sendable (ToolbarSide) async -> Void
    var loadActiveToolID: @Sendable () async -> ToolID
    var saveActiveToolID: @Sendable (ToolID) async -> Void
    var loadTemplate: @Sendable () async -> CanvasTemplate
    var saveTemplate: @Sendable (CanvasTemplate) async -> Void
}

extension DependencyValues {
    var userPreferences: UserPreferencesDependency {
        get { self[UserPreferencesDependency.self] }
        set { self[UserPreferencesDependency.self] = newValue }
    }
}
```

---

## 12. Integration with NotebookFeature

`ToolbarFeature` is scoped as a child of `NotebookFeature` (the toolbar's render-site parent, per §3.2). The parent intercepts forwarded actions and handles them. Earlier iterations had this scoped under `CanvasFeature`; that was wrong because the toolbar is notebook-wide chrome, not per-page state, and the scoping mismatch was the bug that produced page-swipe-translates-the-toolbar.

```swift
struct NotebookFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        let notebookID: UUID
        var notebookTitle: String
        var pages: [NotePageSnapshot] = []
        var currentIndex: Int = 0

        /// Toolbar lives at the notebook level (not per-page) so tool
        /// selection persists across page swipes and `ToolbarWiringView`
        /// renders once as a sibling of the `TabView`.
        var toolbar: ToolbarFeature.State = .init()

        /// Notebook-wide template selection. Owned here so the template
        /// picker panel (rendered at notebook level alongside the
        /// toolbar) can write it and every page reads the same value.
        var activeTemplate: CanvasTemplate = .none
    }

    @CasePathable
    enum Action: Equatable {
        // ... notebook-level actions (pages, navigation) ...
        case templateSelected(CanvasTemplate)
        case toolbar(ToolbarFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.toolbar, action: \.toolbar) {
            ToolbarFeature()
        }

        Reduce { state, action in
            switch action {
            // Notebook-level handlers (page list, current index) ...

            case .templateSelected(let template):
                state.activeTemplate = template
                state.toolbar.openPanel = nil
                return .none

            // Promote the toolbar's forwarded template selection up to
            // the notebook level so all pages share one active template.
            case .toolbar(.templateSelected(let template)):
                return .send(.templateSelected(template))

            case .toolbar:
                return .none
            }
        }
    }
}
```

Forwarded toolbar actions (`undoTapped`, `redoTapped`, `analyzeTapped`, `dispatchTapped`) are handled by `CanvasScreen` reading `toolbarStore` directly — these affect the current page's drawing, not notebook state. Undo / redo are dispatched into the per-page `UndoManager` via `CanvasView.Coordinator`. Analyze hands the current page's `PKDrawing` to `InkTaskExtractor`. Dispatch flips the per-page dispatch panel store's `isVisible`.

**Tool → PencilKit bridge** happens in `CanvasWrapper.updateUIViewController`:

```swift
func updateUIViewController(_ controller: PaperMarkupViewController, context: Context) {
    let toolID = store.toolbar.activeToolID
    let settings = store.toolbar.activeSettings
    if let descriptor = ToolDescriptor.allWritingTools.first(where: { $0.id == toolID }) {
        let pkTool = descriptor.makePKTool(settings)
        if controller.tool != pkTool {
            controller.tool = pkTool
        }
    }
}
```

---

## 13. Testing

> **Source of truth:** `FromInkTests/ToolbarFeatureTests.swift`. The
> snippets below sketch the intended coverage shape — the **Action
> names** in this section are out of date relative to the current
> reducer (e.g. `toolSelected` here is `toolTapped` in code, `previousToolID`
> here is the `toolStack` array in code, `strokeCountUpdated` is now
> `boltVisibilityChanged(Bool)`). Read the test file for the current
> action vocabulary. Plan to refresh these examples when the next
> testing section pass lands.

### 13.1 Tool selection

```swift
func test_selectTool() async {
    let store = TestStore(
        initialState: ToolbarFeature.State(activeToolID: .pen),
        reducer: { ToolbarFeature() }
    )

    await store.send(.toolSelected(.marker)) {
        $0.previousToolID = .pen
        $0.activeToolID = .marker
    }
}

func test_selectSameTool_noOp() async {
    let store = TestStore(
        initialState: ToolbarFeature.State(activeToolID: .pen),
        reducer: { ToolbarFeature() }
    )

    await store.send(.toolSelected(.pen))
    // No state change — guard returns .none
}
```

### 13.2 Pencil double-tap

```swift
func test_pencilDoubleTap_togglesEraser() async {
    let store = TestStore(
        initialState: ToolbarFeature.State(activeToolID: .fountain),
        reducer: { ToolbarFeature() }
    )

    await store.send(.pencilDoubleTapped) {
        $0.previousToolID = .fountain
        $0.activeToolID = .eraser
    }

    await store.send(.pencilDoubleTapped) {
        $0.activeToolID = .fountain
    }
}
```

### 13.3 Two-finger hold

```swift
func test_twoFingerHold_temporaryLasso() async {
    let store = TestStore(
        initialState: ToolbarFeature.State(activeToolID: .pen),
        reducer: { ToolbarFeature() }
    )

    await store.send(.twoFingerHoldBegan) {
        $0.previousToolID = .pen
        $0.activeToolID = .lasso
    }

    await store.send(.twoFingerHoldEnded) {
        $0.activeToolID = .pen
    }
}
```

### 13.4 Panel toggling

```swift
func test_doubleTapTool_togglesPanel() async {
    let store = TestStore(
        initialState: ToolbarFeature.State(activeToolID: .pen),
        reducer: { ToolbarFeature() }
    )

    await store.send(.toolDoubleTapped(.pen)) {
        $0.openPanel = .toolCustomization(.pen)
    }

    await store.send(.toolDoubleTapped(.pen)) {
        $0.openPanel = nil
    }
}
```

### 13.5 Bolt visibility

```swift
func test_boltAppearsAt10Strokes() async {
    let store = TestStore(
        initialState: ToolbarFeature.State(),
        reducer: { ToolbarFeature() }
    )

    await store.send(.strokeCountUpdated(9))
    XCTAssertFalse(store.state.isBoltVisible)

    await store.send(.strokeCountUpdated(10))
    XCTAssertTrue(store.state.isBoltVisible)
}
```

### 13.6 Settings persistence

```swift
func test_toolSettingsChange_persists() async {
    var savedID: ToolID?
    var savedSettings: PenSettings?

    let store = TestStore(
        initialState: ToolbarFeature.State(),
        reducer: { ToolbarFeature() },
        withDependencies: {
            $0.userPreferences.saveToolSettings = { id, settings in
                savedID = id
                savedSettings = settings
            }
        }
    )

    let newSettings = PenSettings(penType: .fineliner, thicknessIndex: 3)
    await store.send(.toolSettingsChanged(.pen, newSettings)) {
        $0.toolSettings[id: .pen] = ToolSettingsEntry(id: .pen, settings: newSettings)
    }

    XCTAssertEqual(savedID, .pen)
    XCTAssertEqual(savedSettings, newSettings)
}
```

### 13.7 Snapshot testing

Per View Layer EDD §14.2, snapshot tests target stateless views. `ToolbarView` is a feature view — snapshot-testable via `FeaturePreview`:

```swift
struct ToolbarViewPreview: FeaturePreview {
    enum State: String, Hashable, CaseIterable {
        case penSelected = "Pen Selected"
        case eraserSelected = "Eraser Selected"
        case boltVisible = "Bolt Visible"
        case leftSide = "Left Side"
        case rightSide = "Right Side"
    }

    // makeViewModel(for:) builds ToolbarView.Model for each state
}
```

---

## 14. Open questions

| # | Question | Impact |
|---|---|---|
| 1 | Should `PenSettings` be split into per-tool-type settings? | A marker doesn't need `graphiteGrade`. Per-tool settings types are more precise but add complexity. |
| 2 | Should toolbar zones be user-configurable? | Reordering tools, hiding unused ones. Significant UX and persistence work. |
| 3 | How should Apple Pencil squeeze map? | `UIPencilInteraction.preferredSqueezeAction` (iOS 17.5+). Could toggle last tool, open quick actions, or show tool picker. |
| 4 | Should the bolt zone be a toolbar zone or a CanvasFeature overlay? | It has unique visibility rules driven by stroke count. Keeping it as a zone is uniform; an overlay keeps the toolbar simpler. |
| 5 | Should `ToolDescriptor` carry a `customizationPanelKind` instead of just `hasCustomization: Bool`? | Would allow different panel types per tool without switch statements in the wiring view. |

---

## 15. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-09 | Toolbar state in TCA, not `@State`. | Testability via `TestStore`. Every gesture and tool switch is verifiable. |
| 2026-05-09 | `ToolID` struct, not enum. | Open for extension. No exhaustive switches. |
| 2026-05-09 | `ToolDescriptor` struct, not protocol. | Protocols with closures don't conform to `Equatable`/`Sendable` cleanly. A struct with an `id`-based `Equatable` conformance is simpler. |
| 2026-05-09 | Toolbar zones as data, not hardcoded VStack. | Adding a tool or action is a configuration change. |
| 2026-05-09 | Three-tier view layer for toolbar. | Matches View Layer EDD §4. Component buttons, feature layout, wiring adapter. |
| 2026-05-09 | Parent `CanvasFeature` handles undo/redo/analyze. | These are canvas concerns, not toolbar concerns. Toolbar forwards via action; parent intercepts. |
| 2026-05-09 | Per-tool settings persisted in `UserPreferences`. | Users expect pen thickness to survive app restart. |
| 2026-05-09 | `PenSettings` binding passed alongside Model, not embedded. | Per View Layer EDD §9 — `@Bindable` observation requires reference semantics. |
