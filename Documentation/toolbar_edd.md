# EDD — Toolbar System

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-09 |
| Implements ticket | F-07 (CanvasFeature) |
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
12. [Integration with CanvasFeature](#12-integration-with-canvasfeature)
13. [Testing](#13-testing)
14. [Open questions](#14-open-questions)
15. [Decision log](#15-decision-log)

---

## 1. Summary

The toolbar is a TCA child feature scoped under `CanvasFeature`. It manages tool selection, per-tool settings, panel presentation, toolbar side, and template selection. The view layer follows the three-tier taxonomy: component views for buttons and panels, a feature view for layout, and a wiring view for Store binding. Apple Pencil gestures (double-tap, squeeze) and drag-to-switch-sides flow through the reducer as discrete actions — they do not bypass TCA.

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
CanvasFeature (@Reducer)
  └─ Scope(state: \.toolbar, action: \.toolbar)
       └─ ToolbarFeature (@Reducer)
            ├─ State: activeToolID, previousToolID, toolSettings, openPanel, side, template
            ├─ Action: toolSelected, toolDoubleTapped, pencilDoubleTapped, ...
            └─ Dependencies: @Dependency(\.userPreferences)

CanvasWiringView
  └─ ToolbarWiringView (Store → Model)
       └─ ToolbarView (feature view, no TCA)
            ├─ ToolButtonView (component)
            ├─ ActionButtonView (component)
            └─ DragHandleView (component)
```

**Layer mapping per View Layer EDD §4:**

| View | Tier | Imports TCA | Accepts |
|---|---|---|---|
| `ToolButtonView` | Component | No | `Model` + `Style` |
| `ActionButtonView` | Component | No | `Model` + `Style` |
| `DragHandleView` | Component | No | `Model` + `Style` |
| `ToolbarView` | Feature | No | `let model: Model` |
| `ToolbarWiringView` | Wiring | Yes | `StoreOf<ToolbarFeature>` |

---

## 4. ToolbarFeature reducer

```swift
@Reducer
struct ToolbarFeature {
    @ObservableState
    struct State: Equatable {
        var activeToolID: ToolID = .pen
        var previousToolID: ToolID = .pen
        var toolSettings: IdentifiedArrayOf<ToolSettingsEntry> = []
        var openPanel: PanelKind? = nil
        var side: ToolbarSide = .left
        var template: CanvasTemplate = .none
        var strokeCount: Int = 0

        var isBoltVisible: Bool { strokeCount >= 10 }

        var activeSettings: PenSettings {
            toolSettings[id: activeToolID]?.settings ?? .default
        }
    }

    enum Action {
        // Tool selection
        case toolSelected(ToolID)
        case toolDoubleTapped(ToolID)
        case pencilDoubleTapped
        case pencilSqueezed
        case twoFingerHoldBegan
        case twoFingerHoldEnded

        // Settings
        case toolSettingsChanged(ToolID, PenSettings)

        // Panels
        case panelToggled(PanelKind)
        case panelDismissed

        // Template
        case templateSelected(CanvasTemplate)

        // Chrome
        case sideChanged(ToolbarSide)
        case strokeCountUpdated(Int)

        // Forwarded to parent (return .none here)
        case undoTapped
        case redoTapped
        case analyzeTapped

        // Lifecycle
        case onAppear
        case settingsLoaded(IdentifiedArrayOf<ToolSettingsEntry>, ToolbarSide, ToolID, CanvasTemplate)
    }

    @Dependency(\.userPreferences) var preferences

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // MARK: - Tool selection

            case .toolSelected(let id):
                guard id != state.activeToolID else { return .none }
                state.previousToolID = state.activeToolID
                state.activeToolID = id
                state.openPanel = nil
                return .none

            case .toolDoubleTapped(let id):
                if state.openPanel == .toolCustomization(id) {
                    state.openPanel = nil
                } else {
                    state.activeToolID = id
                    state.openPanel = .toolCustomization(id)
                }
                return .none

            case .pencilDoubleTapped:
                if state.activeToolID == .eraser {
                    state.activeToolID = state.previousToolID
                } else {
                    state.previousToolID = state.activeToolID
                    state.activeToolID = .eraser
                }
                return .none

            case .pencilSqueezed:
                return .none // reserved

            case .twoFingerHoldBegan:
                state.previousToolID = state.activeToolID
                state.activeToolID = .lasso
                return .none

            case .twoFingerHoldEnded:
                state.activeToolID = state.previousToolID
                return .none

            // MARK: - Settings

            case .toolSettingsChanged(let id, let settings):
                state.toolSettings[id: id] = ToolSettingsEntry(id: id, settings: settings)
                return .run { _ in
                    await preferences.saveToolSettings(id, settings)
                }

            // MARK: - Panels

            case .panelToggled(let kind):
                state.openPanel = state.openPanel == kind ? nil : kind
                return .none

            case .panelDismissed:
                state.openPanel = nil
                return .none

            // MARK: - Template

            case .templateSelected(let template):
                state.template = template
                state.openPanel = nil
                return .run { _ in
                    await preferences.saveTemplate(template)
                }

            // MARK: - Chrome

            case .sideChanged(let side):
                state.side = side
                return .run { _ in
                    await preferences.saveToolbarSide(side)
                }

            case .strokeCountUpdated(let count):
                state.strokeCount = count
                return .none

            // MARK: - Forwarded to parent

            case .undoTapped, .redoTapped, .analyzeTapped:
                return .none

            // MARK: - Lifecycle

            case .onAppear:
                return .run { send in
                    let settings = await preferences.loadToolSettings()
                    let side = await preferences.loadToolbarSide()
                    let toolID = await preferences.loadActiveToolID()
                    let template = await preferences.loadTemplate()
                    await send(.settingsLoaded(settings, side, toolID, template))
                }

            case .settingsLoaded(let settings, let side, let toolID, let template):
                state.toolSettings = settings
                state.side = side
                state.activeToolID = toolID
                state.template = template
                return .none
            }
        }
    }
}
```

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

### 8.2 Feature view

`ToolbarView` is a feature view. No TCA imports. Accepts `let model: Model`. Composes component views from zone data.

```swift
import SwiftUI

struct ToolbarView: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.zones.enumerated()), id: \.element.id) { index, zone in
                if index > 0 {
                    HairlineRule()
                }

                ForEach(Array(zone.items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .toolButton(let buttonModel):
                        ToolButtonView(model: buttonModel)
                    case .actionButton(let buttonModel):
                        ActionButtonView(model: buttonModel)
                    case .bolt(let boltModel):
                        BoltButton(model: boltModel)
                    case .dragHandle(let handleModel):
                        DragHandleView(model: handleModel)
                    }
                }
            }
        }
        .frame(width: model.style.width)
        .background(model.style.background)
        .overlay(alignment: model.borderAlignment) {
            Rectangle()
                .fill(model.style.borderColor)
                .frame(width: 1)
        }
    }
}

extension ToolbarView {
    struct Style {
        let width: CGFloat
        let background: Color
        let borderColor: Color

        static let standard = Style(
            width: LayoutTokens.standard.toolbarWidth,
            background: ColorTokens.standard.surface,
            borderColor: ColorTokens.standard.rule
        )
    }

    struct Model {
        let zones: [Zone]
        let borderAlignment: Alignment
        let style: Style

        init(zones: [Zone], side: ToolbarSide, style: Style = .standard) {
            self.zones = zones
            self.borderAlignment = side == .left ? .trailing : .leading
            self.style = style
        }

        struct Zone: Identifiable {
            let id: String
            let items: [Item]
        }

        enum Item {
            case toolButton(ToolButtonView.Model)
            case actionButton(ActionButtonView.Model)
            case bolt(BoltButton.Model)
            case dragHandle(DragHandleView.Model)
        }
    }
}
```

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
    ToolbarFeature.swift           # @Reducer
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

Panels are presented by `CanvasFeature`'s view layer based on `ToolbarFeature.State.openPanel`. They are component views with Model + Style — no TCA imports.

**PenCustomizationPanel** receives a `Binding<PenSettings>` (per View Layer EDD §9 — bindings passed alongside Model, not embedded in it):

```swift
struct PenCustomizationPanel: View {
    let model: Model
    @Binding var settings: PenSettings

    // ... pen type list, thickness selector, graphite/highlighter options
}

extension PenCustomizationPanel {
    struct Model {
        let toolLabel: String
        let onDismiss: () -> Void
        let style: Style
    }
}
```

The wiring view reads `store.openPanel` and presents the appropriate panel:

```swift
// In CanvasWiringView or ToolbarWiringView parent
if let panel = store.toolbar.openPanel {
    switch panel {
    case .toolCustomization(let toolID):
        PenCustomizationPanel(
            model: .init(
                toolLabel: descriptor(for: toolID).label,
                onDismiss: { store.send(.toolbar(.panelDismissed)) }
            ),
            settings: /* binding via @Bindable — see §9 below */
        )
    case .templatePicker:
        TemplatePickerPanel(...)
    case .canvasSettings:
        CanvasSettingsPanel(...)
    }
}
```

**Binding for PenSettings:** The `PenCustomizationPanel` needs a two-way `Binding<PenSettings>` that writes back to the store. Per View Layer EDD §9, this is passed as a separate parameter. The wiring view constructs it:

```swift
Binding(
    get: { store.toolbar.toolSettings[id: toolID]?.settings ?? .default },
    set: { store.send(.toolbar(.toolSettingsChanged(toolID, $0))) }
)
```

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

## 12. Integration with CanvasFeature

`ToolbarFeature` is scoped as a child of `CanvasFeature`. The parent intercepts forwarded actions and handles them.

```swift
@Reducer
struct CanvasFeature {
    @ObservableState
    struct State: Equatable {
        var toolbar = ToolbarFeature.State()
        var activePageIndex: Int = 0
        var pageIDs: [UUID] = []
        var isOCRRunning: Bool = false
        // Drawing data is NOT in TCA state — lives in UIKit controller.
    }

    enum Action {
        case toolbar(ToolbarFeature.Action)
        case strokeCompleted
        case drawingDebounced
        case pageChanged(Int)
        case ocrCompleted(String)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.toolbar, action: \.toolbar) {
            ToolbarFeature()
        }

        Reduce { state, action in
            switch action {

            // Parent handles forwarded toolbar actions
            case .toolbar(.undoTapped):
                return .run { _ in /* undoManager.undo() via coordinator */ }

            case .toolbar(.redoTapped):
                return .run { _ in /* undoManager.redo() via coordinator */ }

            case .toolbar(.analyzeTapped):
                return .run { send in /* trigger page analysis */ }

            // Tool changes propagate to the canvas coordinator
            // via updateUIViewController reading store.toolbar.activeToolID
            case .toolbar(.toolSelected), .toolbar(.pencilDoubleTapped),
                 .toolbar(.twoFingerHoldBegan), .toolbar(.twoFingerHoldEnded):
                return .none // CanvasWrapper.updateUIViewController handles it

            case .toolbar:
                return .none

            case .strokeCompleted:
                state.toolbar.strokeCount += 1
                return .none

            // ... other canvas actions
            default:
                return .none
            }
        }
    }
}
```

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
