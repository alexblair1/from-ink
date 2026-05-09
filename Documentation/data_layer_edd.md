# EDD — View Layer: Stateless SwiftUI + TCA

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-08 |
| Implements ticket | F-06 (TCA root reducer) + F-07 (CanvasFeature) + F-08 (DispatchFeature) |
| Supersedes | "Stateless SwiftUI + TCA Architecture" reference doc |
| Companion doc | EDD — Data Layer: SwiftData + CloudKit |

---

## Table of contents

1. [Summary](#1-summary)
2. [Goals & non-goals](#2-goals--non-goals)
3. [Core philosophy](#3-core-philosophy)
4. [View taxonomy](#4-view-taxonomy)
5. [Component views](#5-component-views)
6. [The Style pattern](#6-the-style-pattern)
7. [Feature views](#7-feature-views)
8. [The wiring layer (modern TCA)](#8-the-wiring-layer-modern-tca)
9. [Bindings under @ObservableState](#9-bindings-under-observablestate)
10. [Imperative boundaries — the canvas exception](#10-imperative-boundaries--the-canvas-exception)
11. [Shared state across features](#11-shared-state-across-features)
12. [Navigation](#12-navigation)
13. [The FeaturePreview pattern](#13-the-featurepreview-pattern)
14. [Testing strategy](#14-testing-strategy)
15. [Reducer integration with SwiftData](#15-reducer-integration-with-swiftdata)
16. [Anti-patterns](#16-anti-patterns)
17. [Decision framework](#17-decision-framework)
18. [File naming conventions](#18-file-naming-conventions)
19. [Migration path for legacy WithViewStore code](#19-migration-path-for-legacy-withviewstore-code)
20. [Open questions](#20-open-questions)
21. [Decision log](#21-decision-log)

---

## 1. Summary

From Ink uses **stateless SwiftUI views** driven by **The Composable Architecture (TCA) 1.10+** with `@ObservableState`. Every view falls into one of three tiers — **Component**, **Feature**, or **Wiring** — and the boundaries between tiers are enforced by import constraints. Visual tokens live on `Style` structs, never `@Environment`. The canvas is an explicit exception: 60fps drawing surfaces wrap UIKit imperatively and never round-trip through a reducer.

This EDD covers the entire view + presentation layer. Persistence, schema, and CloudKit sync are in the data layer EDD.

---

## 2. Goals & non-goals

### Goals

- A view's behaviour can be predicted from its `Model` without inspecting global state or environment.
- A single visual configuration drives previews, snapshots, and production simultaneously.
- TCA owns state and effects; views own pixels. The boundary is the wiring layer.
- High-frequency input (Apple Pencil, scroll, gesture velocity) does not pass through reducers.
- Reducer tests run without UIKit, without CloudKit, without real I/O.

### Non-goals

- This EDD does not specify the SwiftData schema — see the data layer EDD.
- This EDD does not cover Foundation Models prompts or Vision OCR pipelines — those are owned by the dependency layer (F-10).
- This EDD does not document the design system tokens themselves — those are F-02.

---

## 3. Core philosophy

Three principles govern the architecture:

1. **Views are functions of data.** Every view receives inputs via a `Model` and emits user intent via closures. Views never fetch, mutate, or observe external state directly.
2. **TCA owns state; views own pixels.** Reducers handle state transitions, side effects, and business logic. Views render whatever they are given.
3. **Define once, use everywhere.** A single `Model` configuration powers Xcode previews, in-app debug menus, snapshot tests, and production. No duplication across contexts.

A fourth principle is implicit but worth naming: **boundaries are physical, not conventional.** A file imports `ComposableArchitecture` or it does not. There is no "soft rule" about when to reach for `Store` — the import is the gate.

---

## 4. View taxonomy

```
┌──────────────────────────────────────────────────────────┐
│                    Wiring View                           │
│  imports ComposableArchitecture                          │
│  owns Store, converts State → Model                      │
│  zero layout                                             │
└────────────────────────┬─────────────────────────────────┘
                         │ passes Model
                         ▼
┌──────────────────────────────────────────────────────────┐
│                   Feature View                           │
│  imports SwiftUI only                                    │
│  accepts let model: Model                                │
│  composes Component Views                                │
│  domain-aware (static strings, feature layout)           │
└────────────────────────┬─────────────────────────────────┘
                         │ passes child Models
                         ▼
┌──────────────────────────────────────────────────────────┐
│                  Component View                          │
│  imports SwiftUI only                                    │
│  accepts let model: Model                                │
│  fully reusable across features                          │
│  zero domain knowledge                                   │
└──────────────────────────────────────────────────────────┘
```

| Property | Component | Feature | Wiring |
|---|---|---|---|
| Imports `ComposableArchitecture` | Never | Never | Always |
| Accepts `Store` | Never | Never | Always |
| Accepts `Model` | Always | Always | Never |
| Domain-aware | No | Yes | Yes |
| Reusable across features | Yes | No | No |
| Contains layout | Yes | Yes | No |
| Contains business logic | Never | Never | Never |
| Snapshot-testable in isolation | Yes | Yes | No |

There is one explicit exception to "Wiring contains no layout" — the canvas wrapper, see §10.

---

## 5. Component views

Atomic, reusable building blocks. Domain-unaware. Driven entirely by a nested `Model` and `Style`.

### 5.1 Contract

- Stateless beyond `@State` for UI-local concerns (animation phase, focus).
- No TCA imports.
- No `@Environment` for design tokens — all visual values flow through `Style`.
- No domain logic — no hardcoded strings, no feature-specific conditionals.
- Single file: view + Model + Style colocated, scoped via `extension`.
- Snapshot-testable in isolation.

### 5.2 Canonical structure

```swift
import SwiftUI

struct ActionCard: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: model.style.spacing) {
                Text(model.title)
                    .font(model.style.titleFont)
                    .foregroundStyle(model.style.titleColor)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(model.style.subtitleFont)
                        .foregroundStyle(model.style.subtitleColor)
                }
            }
            .padding(model.style.padding)
            .background(model.style.background)
        }
        .buttonStyle(.plain)
    }
}

extension ActionCard {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let subtitleFont: Font
        let subtitleColor: Color
        let background: Color
        let spacing: CGFloat
        let padding: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.headline,
            titleColor: ColorTokens.standard.ink,
            subtitleFont: TypographyTokens.standard.subheadline,
            subtitleColor: ColorTokens.standard.secondaryLabel,
            background: ColorTokens.standard.surface,
            spacing: SpacingScale.standard.sm,
            padding: SpacingScale.standard.base
        )
    }

    struct Model {
        let title: String
        let subtitle: String?
        let onTap: () -> Void
        let style: Style

        init(
            title: String,
            subtitle: String? = nil,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.title = title
            self.subtitle = subtitle
            self.onTap = onTap
            self.style = style
        }
    }
}
```

### 5.3 Rules

1. `Model` and `Style` are nested inside `extension` blocks of the view.
2. Use `let model: Model` — never destructure into individual properties.
3. Closures use `() -> Void` or `(ParamType) -> Void`. Never pass domain action enums.
4. Bindings have a specific pattern under modern TCA — see §9.
5. `Style` holds visual tokens. `Model` holds content + actions + per-instance domain values.
6. Avoid configuration flags. Prefer multiple focused components over one Swiss-army view.

### 5.4 When to extract a component

Extract when a UI pattern appears in two or more features with the same visual structure. Do not extract speculatively.

---

## 6. The Style pattern

### 6.1 Why not `@Environment`

Three reasons:

1. **Pure functions of inputs.** `@Environment` introduces a hidden input channel — the view's output depends on something not visible at the call site. This breaks snapshot testing reproducibility and complicates `FeaturePreview` setup (every preview would need an environment injection step).
2. **Dark mode does not require `@Environment`.** Asset-catalog `Color` references resolve adaptively at render time regardless of how they reach the view.
3. **One less thing to wire.** No `.designSystem(.standard)` at the app root, no forgetting to inject in test harnesses.

### 6.2 Content vs. Style

| | `Model` (content) | `Style` (visual) |
|---|---|---|
| Varies per instance | Yes | No (defaults to `.standard`) |
| Domain-specific colors | Yes (notebook `coverColor`) | No |
| Structural colors | No | Yes (`ink`, `surface`, `border`) |
| Action closures | Yes | No |
| Fonts, spacing, sizing | No | Yes |

Heuristic: `Model` is "what to show + what to do." `Style` is "how it looks."

### 6.3 Design-system token types

Style presets are built from static token instances. Plain Swift structs, no `@Environment` dependency:

| Token type | Purpose | Examples |
|---|---|---|
| `ColorTokens.standard` | Adaptive named colors from asset catalog | `.ink`, `.surface`, `.paper`, `.secondaryLabel` |
| `TypographyTokens.standard` | System font presets | `.headline`, `.body`, `.subheadline`, `.monoLabel` |
| `SpacingScale.standard` | 4pt grid | `.sm` (8), `.md` (12), `.base` (16), `.lg` (24) |
| `LayoutTokens.standard` | Fixed chrome dimensions | `.hitTarget` (44), `.dialogWidth` (300) |

All `Color` values in `ColorTokens` are asset-catalog references — they resolve to light or dark variants at render time without additional wiring.

### 6.4 Style presets

A component may define multiple named presets beyond `.standard`:

```swift
extension NotebookSpine.Style {
    static let compact = Style(
        titleFont: TypographyTokens.standard.footnote,
        titleColor: ColorTokens.standard.ink,
        metadataColor: ColorTokens.standard.tertiaryLabel,
        background: ColorTokens.standard.surface,
        stripHeight: 2,
        innerSpacing: SpacingScale.standard.xs,
        padding: SpacingScale.standard.sm,
        minHeight: 80
    )
}

NotebookSpine(model: .init(title: "Notes", onTap: {}, style: .compact))
```

Use sparingly. Most components only need `.standard`. Add presets when a component genuinely appears in two distinct visual contexts.

### 6.5 Rules

1. **`Style` always has `static let standard`** built from design-system tokens.
2. **`Model` always has `style: Style = .standard`** — callers never need to think about styling unless overriding.
3. **Domain-specific colors live on `Model`, not `Style`.** A notebook's cover color is content; the title color is style.
4. **No `@Environment(\.ds)` in component views.** All tokens arrive through `model.style.*`.
5. **No nil-coalescing in the view body.** Don't write `model.color ?? someDefault`. Put the default on the `Style` or `Model` init.
6. **No magic numbers in the view body.** Every font size, spacing value, color comes from `model.style.*` or `model.*`.
7. **Style structs are value types and should be `Sendable`** if the Model needs to be.

### 6.6 Style for feature views

Feature views *may* either follow the same `Style` pattern or reference design tokens directly via a private static reference:

```swift
struct HomeScreen: View {
    let model: Model
    private let ds = DesignSystem.standard  // static, no @Environment
    var body: some View { ... }
}
```

Both are acceptable for feature views because they are not reusable and never need per-instance style overrides. **The `Style` struct pattern is required only for component views**, where reuse across contexts is the whole point.

---

## 7. Feature views

Domain-specific views that compose component views with real content. They know feature terminology, layout, and static strings — but not TCA.

### 7.1 Contract

- Domain-aware: inline static strings, feature-specific layout.
- No TCA imports.
- Accepts `let model: Model`.
- Composes component views by passing child `Model` values.
- Not designed for reuse — scoped to a single feature or screen.

### 7.2 Structure

```swift
import SwiftUI

struct ProfileView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 16) {
            AvatarView(model: model.avatar)
            Text(model.displayName).font(.title2)
            ActionCard(model: model.editAction)
        }
        .padding()
        .onAppear { model.onAppear() }
    }
}

extension ProfileView {
    struct Model {
        let avatar: AvatarView.Model
        let displayName: String
        let editAction: ActionCard.Model
        let onAppear: () -> Void
    }
}
```

### 7.3 Rules

1. Same `let model: Model` pattern as components.
2. The model composes child component models as properties.
3. May use `@State` for UI-only local concerns (animation, scroll, focus) that have no meaning to the reducer.
4. Navigation presentation uses `Binding<Bool>` or `Binding<Item?>` properties on the model — see §9 and §12.
5. Purpose-built. If you find yourself modifying a feature view to fit a second context, extract the shared parts into a component.

---

## 8. The wiring layer (modern TCA)

The wiring layer connects TCA to the stateless view hierarchy. It has two parts: the **Wiring View** and the **Adapter**.

### 8.1 The modern API — `@ObservableState`, no `WithViewStore`

From Ink uses TCA 1.10+, which deprecated `WithViewStore` and `ViewStoreOf`. State observation flows through the `@ObservableState` macro and SwiftUI's `Observation` framework. The wiring view holds a `Store` directly — no wrapper, no closure.

```swift
import SwiftUI
import ComposableArchitecture

struct ProfileWiringView: View {
    let store: StoreOf<ProfileFeature>

    var body: some View {
        ProfileView(model: .init(store: store))
    }
}
```

The reducer's state must be marked `@ObservableState`:

```swift
@Reducer
struct ProfileFeature {
    @ObservableState
    struct State: Equatable {
        var displayName: String = ""
        var isEditing: Bool = false
    }

    enum Action {
        case editTapped
        case saveTapped
        case onAppear
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .editTapped:
                state.isEditing = true
                return .none
            case .saveTapped:
                state.isEditing = false
                return .none
            case .onAppear:
                return .none
            }
        }
    }
}
```

### 8.2 The adapter

An extension on the feature view's `Model` that provides an `init(store:)`:

```swift
extension ProfileView.Model {
    init(store: StoreOf<ProfileFeature>) {
        self.avatar = AvatarView.Model(
            imageURL: store.avatarURL,
            initials: store.initials
        )
        self.displayName = store.displayName
        self.editAction = ActionCard.Model(
            title: "Edit Profile",
            onTap: { store.send(.editTapped) }
        )
        self.onAppear = { store.send(.onAppear) }
    }
}
```

**Important note on observation granularity.** Reading `store.displayName` and `store.avatarURL` registers those properties for observation. SwiftUI re-evaluates the body when those (and only those) change. However, building a `Model` struct that captures all properties up front means *every* property read happens on every body invocation. For complex screens this can over-observe.

Mitigation: keep adapters small and feature views shallow. If a screen has many independent moving parts (e.g. the dispatch inbox with N task cards), pass child stores via `store.scope(...)` and let each child wiring view do its own narrow observation:

```swift
struct DispatchInboxWiringView: View {
    @Bindable var store: StoreOf<DispatchFeature>

    var body: some View {
        DispatchInboxView(
            model: .init(store: store),
            taskCards: store.scope(state: \.tasks, action: \.tasks)
                .compactMap { taskStore in
                    TaskCardWiringView(store: taskStore)
                }
        )
    }
}
```

This is more nuanced than the simple "build a Model and pass it" pattern, and is only needed when measurable re-render churn appears.

### 8.3 File organisation

```
Features/Profile/
  ProfileFeature.swift                # @Reducer — State, Action, body
  Views/
    ProfileView.swift                 # Feature view (no TCA)
    ProfileWiringView.swift           # Wiring view (TCA integration)
  Adapters/
    ProfileView+Adapter.swift         # Model init(store:)
  Components/                         # Feature-local components (optional)
  Previews/
    ProfileViewPreview.swift          # FeaturePreview conformance
```

### 8.4 Rules

1. The wiring view is the **only** place in the view layer that imports `ComposableArchitecture`. (Adapters also import it but live in their own folder.)
2. The adapter is the **only** place that maps reducer actions to closures.
3. Wiring views contain no layout — exactly one expression in the body.
4. Replace direct feature-view usage with wiring view at call sites:
   ```swift
   // Before
   ProfileView(store: store)
   // After
   ProfileWiringView(store: store)
   ```

### 8.5 Simplified variant

For small adapters, combine the wiring view and adapter into one file:

```swift
struct ProfileWiringView: View {
    let store: StoreOf<ProfileFeature>

    var body: some View {
        ProfileView(model: Self.makeModel(store: store))
    }

    private static func makeModel(store: StoreOf<ProfileFeature>) -> ProfileView.Model {
        ProfileView.Model(
            avatar: .init(imageURL: store.avatarURL, initials: store.initials),
            displayName: store.displayName,
            editAction: .init(title: "Edit Profile", onTap: { store.send(.editTapped) }),
            onAppear: { store.send(.onAppear) }
        )
    }
}
```

Use the separated pattern (wiring view + adapter file) when the adapter exceeds ~40 lines or when child components need their own adapter extensions.

---

## 9. Bindings under @ObservableState

Two-way bindings (text fields, toggles, sliders) need special handling. Embedding a `Binding<T>` inside a value-type `Model` works mechanically but breaks `@Bindable`'s observation tracking — the binding's get/set closures don't participate in TCA's observation graph correctly.

### 9.1 The pattern — `@Bindable` at the wiring view, bindings passed alongside the Model

```swift
@Reducer
struct SearchFeature {
    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var results: [Result] = []
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case searchSubmitted
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                // react to query changes
                return .none
            case .binding:
                return .none
            case .searchSubmitted:
                return .none
            }
        }
    }
}

struct SearchWiringView: View {
    @Bindable var store: StoreOf<SearchFeature>

    var body: some View {
        SearchView(
            model: .init(store: store),
            queryBinding: $store.query
        )
    }
}

extension SearchView {
    struct Model {
        let results: [Result]
        let onSubmit: () -> Void
        let style: Style
    }
}

struct SearchView: View {
    let model: Model
    @Binding var queryBinding: String

    var body: some View {
        VStack {
            TextField("Search", text: $queryBinding)
                .onSubmit { model.onSubmit() }
            ResultList(results: model.results)
        }
    }
}
```

### 9.2 Why this pattern

- `@Bindable var store` enables `$store.query` to produce a real, observable binding tied to the store.
- The binding is passed as a separate parameter, *not* embedded in the Model. Models stay value-type and predictable; bindings retain their reference semantics.
- `BindableAction` and `BindingReducer()` handle the dispatch — no `viewStore.binding(get:send:)` boilerplate.

### 9.3 When the binding count is large

A form with 10 fields would need 10 binding parameters. In that case, use a `@Bindable` reference directly in the feature view:

```swift
struct OnboardingFormView: View {
    @Bindable var store: StoreOf<OnboardingFeature>
    let model: Model    // for non-binding content + actions

    var body: some View {
        Form {
            TextField("Name", text: $store.name)
            TextField("Email", text: $store.email)
            // ...
        }
    }
}
```

This bends the "feature views don't import TCA" rule — but it is the lesser evil compared to passing 10 bindings as parameters. **Treat as an exception, not a default.** Forms with many bindings are the canonical case; settings screens are another.

---

## 10. Imperative boundaries — the canvas exception

The canvas (`PaperMarkupViewController` from PaperKit, or `PKCanvasView` from PencilKit) emits drawing-changed events at up to 240Hz on Apple Pencil. Routing those events through a TCA reducer would mean dispatching ~240 actions per second per active stroke. This is unacceptable.

**The rule.** Apple Pencil input, scroll position, and any UIKit/AppKit controller wrapped via `UIViewRepresentable` / `NSViewRepresentable` / `UIViewControllerRepresentable` does NOT pass through a reducer. It stays inside UIKit until a meaningful event boundary is crossed.

### 10.1 The pattern

```swift
import SwiftUI
import PaperKit
import ComposableArchitecture

struct CanvasWrapper: UIViewControllerRepresentable {
    let store: StoreOf<CanvasFeature>

    func makeUIViewController(context: Context) -> PaperMarkupViewController {
        let controller = PaperMarkupViewController(/* ... */)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PaperMarkupViewController, context: Context) {
        // Apply only structural changes from store — tool selection, page swap, undo/redo.
        // NEVER apply drawing data here on every update; that would round-trip 60fps changes.
        let state = store.state
        if controller.activeTool != state.activeTool {
            controller.activeTool = state.activeTool
        }
        if controller.currentPageIndex != state.activePageIndex {
            controller.loadPage(at: state.activePageIndex)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    final class Coordinator: PaperMarkupViewControllerDelegate {
        let store: StoreOf<CanvasFeature>
        private var saveDebounceTask: Task<Void, Never>?

        init(store: StoreOf<CanvasFeature>) {
            self.store = store
        }

        // High-frequency: do NOT send to store. Only buffer.
        func paperMarkup(_ vc: PaperMarkupViewController, didChange drawing: PaperMarkup) {
            saveDebounceTask?.cancel()
            saveDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                store.send(.drawingDebounced(drawing))
            }
        }

        // Low-frequency: send directly.
        func paperMarkupDidEndStroke(_ vc: PaperMarkupViewController) {
            store.send(.strokeCompleted)
        }
    }
}
```

### 10.2 What lives in `CanvasFeature.State`

```swift
@Reducer
struct CanvasFeature {
    @ObservableState
    struct State: Equatable {
        var activeTool: PaperTool = .pen
        var activePageIndex: Int = 0
        var pageIDs: [UUID] = []
        var isOCRRunning: Bool = false
        var sessionStartedAt: Date?

        // NOT here: PaperMarkup, PKDrawing, stroke arrays.
        // Drawing data lives in SwiftData via NotePage.drawingData.
    }

    enum Action {
        case toolSelected(PaperTool)
        case pageChanged(Int)
        case strokeCompleted
        case drawingDebounced(PaperMarkup)
        case ocrCompleted(String)
        case sessionTimedOut
    }
}
```

### 10.3 Rules

1. **Drawing data is never in TCA state.** It lives in the UIKit controller and is persisted to SwiftData on debounced save.
2. **Tool selection, page index, undo/redo IS in TCA state.** These are low-frequency and need to survive view recreation.
3. **The `Coordinator` is the bridge.** It receives high-frequency callbacks, buffers them, and only sends to the store at meaningful boundaries (debounced save, end-of-stroke, end-of-session).
4. **`updateUIViewController` does not write drawing data.** It applies only structural state changes. Writing drawing data here would create a feedback loop (state → UIKit → callback → state).

### 10.4 Other imperative boundaries

This is not unique to the canvas. The same pattern applies to:

- **`PDFView`** from PDFKit — annotation events are high-frequency; only persist on commit.
- **External display mirroring** — frame updates run at 60fps and must not hit the reducer.
- **`AVAudioRecorder`** if audio capture ever ships — peak metering at 30Hz.
- **Companion mode handoff** via `NSUserActivity` — intermediate updates do not need to flow through state.

The general rule: **if the source emits events faster than ~10Hz, debounce or threshold before sending to the store.**

---

## 11. Shared state across features

`AppFeature` composes six child features (`Library`, `Canvas`, `Dispatch`, `Onboarding`, `Settings`, `Navigation`). Some state needs to be visible to multiple features — extracted tasks originated in `CanvasFeature` need to appear in `DispatchFeature`'s inbox.

### 11.1 Three patterns, in order of preference

**Pattern 1 — Persist, query, observe.**
The canonical pattern. `CanvasFeature` writes `ExtractedTask` rows to SwiftData. `DispatchFeature` reads them via a query in `onAppear`. Works because SwiftData is the source of truth for cross-feature state, and TCA state is the *view* of that truth.

```swift
case .canvas(.sessionExtracted(let tasks)):
    return .run { _ in
        let context = modelContext()
        for task in tasks {
            context.insert(task)
        }
        try context.save()
    }

case .dispatch(.onAppear):
    return .run { send in
        let context = modelContext()
        let tasks = try context.fetch(
            FetchDescriptor<ExtractedTask>(
                predicate: #Predicate { $0.statusRaw == "pending" }
            )
        )
        await send(.dispatch(.tasksLoaded(tasks)))
    }
```

**Pattern 2 — Parent-action handling.**
The parent reducer intercepts a child action and routes it. Use when the cross-feature signal does not need to persist.

```swift
var body: some ReducerOf<Self> {
    Scope(state: \.canvas, action: \.canvas) { CanvasFeature() }
    Scope(state: \.dispatch, action: \.dispatch) { DispatchFeature() }

    Reduce { state, action in
        switch action {
        case .canvas(.sessionExtracted(let tasks)):
            state.dispatch.pendingTasks.append(contentsOf: tasks)
            return .none
        default:
            return .none
        }
    }
}
```

**Pattern 3 — `@Shared` state (TCA 1.10+).**
TCA's `@Shared` property wrapper. Use sparingly — it makes state ownership ambiguous and complicates testing. Reserve for genuinely shared values that don't fit Pattern 1 (e.g. transient UI state visible across multiple feature stacks).

### 11.2 Default to Pattern 1

If the data has any persistence semantics — survives a relaunch, syncs to other devices — it belongs in SwiftData and the TCA state is just a cached view. Pattern 2 is for ephemeral handoffs. Pattern 3 is the last resort.

---

## 12. Navigation

TCA 1.10+ provides `NavigationStack` integration via `@Presents` and `@Reducer` destinations. Navigation state lives in the reducer, not in views.

### 12.1 Stack-based navigation

```swift
@Reducer
struct LibraryFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
    }

    enum Action {
        case path(StackActionOf<Path>)
        case notebookTapped(UUID)
    }

    @Reducer
    enum Path {
        case canvas(CanvasFeature)
        case settings(SettingsFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .notebookTapped(let id):
                state.path.append(.canvas(CanvasFeature.State(notebookID: id)))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

struct LibraryWiringView: View {
    @Bindable var store: StoreOf<LibraryFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            LibraryView(model: .init(store: store))
        } destination: { store in
            switch store.case {
            case .canvas(let canvasStore):
                CanvasWiringView(store: canvasStore)
            case .settings(let settingsStore):
                SettingsWiringView(store: settingsStore)
            }
        }
    }
}
```

### 12.2 Sheet and full-screen presentation

Use `@Presents` for presented destinations:

```swift
@ObservableState
struct State: Equatable {
    @Presents var newNotebookSheet: NewNotebookFeature.State?
}

enum Action {
    case newNotebookSheet(PresentationAction<NewNotebookFeature.Action>)
    case createNotebookTapped
}
```

The wiring view binds via `$store.scope(state: \.newNotebookSheet, action: \.newNotebookSheet)`.

### 12.3 No `NavigationRouter`

Pre-pivot designs included an `@Observable NavigationRouter`. **That is replaced by TCA navigation.** F-04 should be updated to describe `NavigationFeature` rather than a free-standing observable router.

---

## 13. The FeaturePreview pattern

A single configuration powers three things:

1. **In-app debug menu** — browsable by developers.
2. **Snapshot tests** — automated visual regression.
3. **Xcode previews** — not the canonical path, but supported.

### 13.1 Protocol definition

```swift
protocol FeaturePreview: View {
    associatedtype PreviewState: Hashable, CaseIterable
    associatedtype ViewModel
    associatedtype FeatureView: View

    var state: PreviewState { get }
    static var debugFeature: DebugFeature { get }
    func makeViewModel(for state: PreviewState) -> ViewModel
}
```

**Note on `ViewModel` constraint.** `ViewModel` is **not** required to conform to `Equatable`. Models contain closures (`() -> Void`), which are not equatable. The protocol does not impose a constraint that cannot be satisfied.

### 13.2 Implementation

```swift
struct ProfileViewPreview: FeaturePreview {
    enum State: String, Hashable, CaseIterable {
        case populated = "Populated"
        case longName = "Long Name"
        case noAvatar = "No Avatar"
        case empty = "Empty"
    }

    typealias PreviewState = State
    typealias ViewModel = ProfileView.Model
    typealias FeatureView = ProfileView

    let state: State

    var body: some View {
        ProfileView(model: makeViewModel(for: state))
    }

    static var debugFeature: DebugFeature {
        DebugFeature(
            title: "ProfileView",
            states: State.allCases.map { state in
                .preview(title: state.rawValue, ProfileViewPreview(state: state))
            }
        )
    }

    func makeViewModel(for state: State) -> ProfileView.Model {
        switch state {
        case .populated:
            return .init(
                avatar: .init(imageURL: URL(string: "https://example.com/a.jpg"), initials: "AB"),
                displayName: "Alex Blair",
                editAction: .init(title: "Edit Profile", onTap: {}),
                onAppear: {}
            )
        case .longName:
            return .init(
                avatar: .init(imageURL: nil, initials: "AB"),
                displayName: "Alexander Bartholomew Blair-Richardson III",
                editAction: .init(title: "Edit Profile", onTap: {}),
                onAppear: {}
            )
        case .noAvatar:
            return .init(
                avatar: .init(imageURL: nil, initials: "AB"),
                displayName: "Alex Blair",
                editAction: .init(title: "Edit Profile", onTap: {}),
                onAppear: {}
            )
        case .empty:
            return .init(
                avatar: .init(imageURL: nil, initials: "?"),
                displayName: "Unknown User",
                editAction: .init(title: "Edit Profile", onTap: {}),
                onAppear: {}
            )
        }
    }
}
```

### 13.3 Debug menu registry

```swift
enum VerticalRegistry: String, CaseIterable {
    case library = "Library"
    case canvas = "Canvas"
    case dispatch = "Dispatch"
    case onboarding = "Onboarding"
    case reusableViews = "Reusable Views"

    var features: [DebugFeature] {
        switch self {
        case .library:        return [LibraryViewPreview.debugFeature]
        case .canvas:         return [CanvasViewPreview.debugFeature]
        case .dispatch:       return [DispatchInboxViewPreview.debugFeature]
        case .onboarding:     return [OnboardingViewPreview.debugFeature]
        case .reusableViews:  return [ActionCardPreview.debugFeature, AvatarPreview.debugFeature]
        }
    }
}
```

### 13.4 Benefits

| Benefit | Mechanism |
|---|---|
| Single source of truth | `makeViewModel(for:)` creates all fixtures in one place |
| Compile-time safety | `CaseIterable` enum — missing states will not compile if a switch is exhaustive |
| Self-documenting | Enum cases enumerate every visual variant |
| No duplication | Same struct powers debug menu and snapshot tests |
| Discoverability | `VerticalRegistry` lists everything in one place |

---

## 14. Testing strategy

Each layer has a dedicated approach. No layer requires the testing infrastructure of another.

### 14.1 Layer 1 — Reducer tests via `TestStore`

Test state transitions and effects in isolation. No views.

```swift
import ComposableArchitecture
import XCTest

final class ProfileFeatureTests: XCTestCase {
    func test_editTapped_setsEditingTrue() async {
        let store = TestStore(
            initialState: ProfileFeature.State(displayName: "Alex"),
            reducer: { ProfileFeature() }
        )

        await store.send(.editTapped) {
            $0.isEditing = true
        }
    }
}
```

**Rules:**

- Every action and state mutation is asserted explicitly.
- When an action produces no state changes, omit the trailing closure.
- All dependencies use `testValue` — deterministic fixtures, no real I/O.
- `ModelContext` is injected via the in-memory dependency (see §15).

### 14.2 Layer 2 — Snapshot tests via `FeaturePreview`

Test visual output of stateless views. No `Store`.

```swift
import SnapshotTesting
import XCTest

final class ProfileViewSnapshotTests: XCTestCase {
    func testProfilePopulated() {
        assertSnapshot(
            of: ProfileViewPreview(state: .populated),
            as: .image(layout: .device(config: .iPhone16))
        )
    }

    func testProfileLongName() {
        assertSnapshot(
            of: ProfileViewPreview(state: .longName),
            as: .image(layout: .device(config: .iPhone16))
        )
    }

    func testProfileEmpty() {
        assertSnapshot(
            of: ProfileViewPreview(state: .empty),
            as: .image(layout: .device(config: .iPhone16))
        )
    }
}
```

**Rules:**

- Snapshot tests target stateless views only — never wiring views that require a `Store`.
- Use the `FeaturePreview` struct as the view under test.
- Test every `CaseIterable` state. If a state exists, it is tested.
- Use `record: true` to capture new baselines; switch to `record: false` once approved.

### 14.3 Layer 3 — Adapter tests (optional)

For complex adapters, verify the mapping from store state to `Model`:

```swift
func test_adapter_mapsDisplayName() {
    let store = Store(initialState: ProfileFeature.State(displayName: "Alex Blair")) {
        ProfileFeature()
    }
    let model = ProfileView.Model(store: store)
    XCTAssertEqual(model.displayName, "Alex Blair")
}
```

Most adapters are simple enough that reducer tests + snapshot tests suffice. Add adapter tests only when the mapping contains non-trivial logic (formatting, filtering, sorting).

### 14.4 Coverage summary

| What is tested | How | Requires Store |
|---|---|---|
| State transitions | `TestStore` | Yes |
| Side effects | `TestStore` with mocked dependencies | Yes |
| SwiftData reads/writes | `TestStore` + in-memory `ModelContainer` | Yes |
| Visual output | Snapshot tests via `FeaturePreview` | No |
| Model mapping | Adapter unit tests (optional) | Yes |

---

## 15. Reducer integration with SwiftData

Reducers that need persistence access use the `@Dependency(\.syncedModelContext)` injected from the data layer EDD §12. The TestStore receives an in-memory container automatically — no additional setup.

### 15.1 Live reducer

```swift
@Reducer
struct LibraryFeature {
    @Dependency(\.syncedModelContext) var modelContext

    @ObservableState
    struct State: Equatable {
        var notebooks: [Notebook] = []
    }

    enum Action {
        case onAppear
        case notebooksLoaded([Notebook])
        case createNotebookTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    let context = modelContext()
                    let notebooks = try context.fetch(
                        FetchDescriptor<Notebook>(
                            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                        )
                    )
                    await send(.notebooksLoaded(notebooks))
                }

            case .notebooksLoaded(let notebooks):
                state.notebooks = notebooks
                return .none

            case .createNotebookTapped:
                return .run { send in
                    let context = modelContext()
                    context.insert(Notebook(title: "Untitled"))
                    try context.save()
                    // Re-fetch happens via the next .onAppear or via observation.
                }
            }
        }
    }
}
```

### 15.2 Test

```swift
func test_onAppear_loadsNotebooks() async {
    let store = TestStore(
        initialState: LibraryFeature.State(),
        reducer: { LibraryFeature() }
    )
    // testValue of syncedModelContext returns an in-memory container; no setup needed.

    await store.send(.onAppear)
    await store.receive(\.notebooksLoaded) {
        $0.notebooks = []  // empty container starts empty
    }
}

func test_createNotebook_insertsRow() async {
    let store = TestStore(
        initialState: LibraryFeature.State(),
        reducer: { LibraryFeature() }
    )

    await store.send(.createNotebookTapped)
    // No state change asserted — the insert is a side effect, surfaced on next .onAppear.

    await store.send(.onAppear)
    await store.receive(\.notebooksLoaded) {
        $0.notebooks.count == 1
    }
}
```

### 15.3 What not to test at the reducer layer

- **Don't assert on raw SwiftData internals** (relationship integrity, cascade behaviour). Those are SwiftData's guarantees, not yours.
- **Don't test CloudKit sync.** It cannot be tested locally; it's exercised in QA.
- **Don't test `@Query`.** `@Query` is a view-layer construct; reducer tests use `FetchDescriptor` directly.

---

## 16. Anti-patterns

### Component view anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Importing `ComposableArchitecture` | Couples the component to TCA | Accept a `Model` |
| Using `@Environment(\.ds)` | Hidden input — view is no longer a pure function of its `Model` | Use a `Style` struct with `.standard` |
| Nil-coalescing colors in body | Obscures the actual default | Put the default on `Style` or `Model` init |
| Magic numbers in body | Undocumented constants divorced from the design system | Reference `model.style.*` |
| Hardcoding domain strings | Breaks reusability and localisation | Pass strings via `Model`; localise via `AppStrings.*` |
| Mixing content and style on `Model` | Unclear what varies vs. what's structural | Separate `Model` from `Style` |
| Conditional logic based on feature context | Violates single-responsibility | Split into separate components |
| `@ObservedObject` or `@EnvironmentObject` | Hidden state dependencies | Use `Model` properties and closures |
| Swiss-army view with config flags | Hard to test, hard to understand | Multiple focused views |
| Embedding `Binding<T>` in a value-type Model | Breaks `@Bindable` observation | Pass binding as a separate parameter (§9) |

### Feature-view anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Generalising for reuse across features | Feature views are purpose-built | Extract shared UI into a component |
| Importing `ComposableArchitecture` | Couples the view to TCA | Use the wiring layer (exception: forms with many bindings — §9.3) |
| Calling services or APIs directly | Views should not produce side effects | Emit intent via closures; reducer handles effects |
| Storing feature state in `@State` | Breaks unidirectional data flow | Move to TCA `State`; only use `@State` for UI-local concerns |

### Wiring-view anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Adding layout or styling | Wiring views are pass-through only | Move layout to the feature view (exception: canvas wrapper — §10) |
| Complex conditional logic | Obscures the mapping | Keep adapter logic in `init(store:)` |
| Using deprecated `WithViewStore` | Deprecated in TCA 1.10+ | Use `@Bindable` and direct store access (§8.1) |
| Reading the entire store eagerly when scoping is possible | Over-observation; unnecessary re-renders | Use `store.scope(...)` for child features (§8.2) |

### Architecture-wide anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Putting `PKDrawing` or `PaperMarkup` in TCA state | 60fps drawing cannot route through a reducer | Imperative boundary at the canvas wrapper (§10) |
| Putting OAuth tokens in SwiftData | CloudKit-syncs credentials inappropriately | Keychain only (data layer EDD §5.7) |
| `@Observable NavigationRouter` outside TCA | Two sources of truth for navigation | Navigation lives in the reducer (§12) |

---

## 17. Decision framework

Use this when creating a new view:

```
Is this view reusable across multiple features?
├── Yes → Component View
│         • No TCA imports
│         • Model + Style structs
│         • Lives in shared Components/
│
└── No → Is this view for a specific feature/screen?
          ├── Yes → Feature View + Wiring View
          │         • Feature: no TCA, accepts Model
          │         • Wiring: owns Store, builds Model
          │         • Adapter: init(store:) extension
          │
          └── No → Probably a Component View
                    (when in doubt, make it stateless and reusable)
```

### 17.1 When to use `@State`

`@State` is permitted in component and feature views for **UI-local concerns** with no meaning to the reducer:

- Animation phase
- Scroll position
- Keyboard focus (`@FocusState`)
- Hover state
- Disclosure/expansion that is purely visual

If the state affects business logic, persistence, or needs to survive navigation, it belongs in the reducer.

### 17.2 When to split vs. inline the wiring layer

| Scenario | Approach |
|---|---|
| Adapter < 40 lines | Inline in wiring view file |
| Adapter > 40 lines | Separate `+Adapter.swift` file |
| Child components need adapters | Separate file per component |
| Feature view < 20 lines | Consider wiring directly to component views |

---

## 18. File naming conventions

```
Features/{FeatureName}/
  {FeatureName}Feature.swift           # @Reducer
  Views/
    {FeatureName}View.swift            # Feature view (stateless)
    {FeatureName}WiringView.swift      # Wiring view (TCA)
  Adapters/
    {FeatureName}View+Adapter.swift    # Model init(store:)
    {ChildComponent}+Adapter.swift     # Child adapters (if needed)
  Previews/
    {FeatureName}ViewPreview.swift     # FeaturePreview conformance

Components/                             # Shared component views
  {ComponentName}.swift                 # View + Model + Style
  Previews/
    {ComponentName}Preview.swift

ImperativeBridges/                      # UIKit/AppKit wrappers
  CanvasWrapper.swift
  PDFAnnotationWrapper.swift

SnapshotTests/
  {FeatureName}ViewSnapshotTests.swift
  Components/
    {ComponentName}SnapshotTests.swift
```

---

## 19. Migration path for legacy WithViewStore code

This section is included for completeness. It does not apply to From Ink (greenfield project) but is preserved for reference.

If a codebase uses `WithViewStore` and `ViewStoreOf`:

1. **Mark all `State` structs `@ObservableState`.**
2. **Remove `WithViewStore` wrappers** — the wiring view body becomes `FeatureView(model: .init(store: store))`.
3. **Change adapters from `init(viewStore: ViewStoreOf<X>)` to `init(store: StoreOf<X>)`.**
4. **Replace `viewStore.binding(...)` with `@Bindable` + `$store.field`** (§9).
5. **Remove `viewStore.send(...)` calls** in adapters; replace with `store.send(...)`.

The mechanical conversion is straightforward; the subtle issue is observation granularity (§8.2). Profile re-render frequency before and after — if a screen suddenly re-renders too often, scope child stores rather than building a flat Model.

---

## 20. Open questions

1. **Forms with many bindings — `@Bindable` in feature view OR keep all wiring in wiring view?** §9.3 allows `@Bindable` directly in the feature view as an exception. Need to decide if onboarding (5-screen form) qualifies. **Default: yes, qualifies.**
2. **Snapshot tests in CI from day one?** Setting up `SnapshotTesting` in the test target costs ~30min. **Default: yes — set up before F-07.**
3. **One `AppFeature` or split into top-level `iOSAppFeature` and `macAppFeature`?** Mac is a different app surface (no canvas, sidebar layout). **Default: one `AppFeature`, condition on `#if os(macOS)` in child reducers where behaviour differs.**
4. **Debug menu shipped in TestFlight builds only, or in App Store?** A hidden gesture in the App Store build feels right for solo dev. **Default: TestFlight only via `#if DEBUG`.**

---

## 21. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-08 | TCA 1.10+ with `@ObservableState`. No `WithViewStore`, no `ViewStoreOf`. | The deprecated APIs would generate the wrong observation semantics. |
| 2026-05-08 | Three-tier view taxonomy (Component / Feature / Wiring). | Boundaries enforced by import. Predictable testing surface. |
| 2026-05-08 | `Style` struct over `@Environment` for design tokens. | Pure functions of inputs; simpler preview/snapshot setup. |
| 2026-05-08 | Bindings passed as separate parameters, not embedded in Model. | `@Bindable` observation requires reference semantics. |
| 2026-05-08 | Canvas (and other 60fps surfaces) bypass TCA via UIKit coordinator. | Reducer cannot keep up with Apple Pencil sample rate. |
| 2026-05-08 | Cross-feature state via SwiftData first, parent action second, `@Shared` last. | Persistence-backed state has the clearest ownership. |
| 2026-05-08 | Navigation lives in TCA reducers via `StackState` and `@Presents`. | One source of truth; replaces `@Observable NavigationRouter`. |
| 2026-05-08 | `FeaturePreview.ViewModel` is NOT `Equatable`. | Closures aren't equatable. |
| 2026-05-08 | `ModelContext` injected via `@Dependency`, not `@Environment`. | Reducer testability with in-memory container. |
| 2026-05-08 | Feature views may use a static `DesignSystem.standard` reference. | Acceptable because feature views are not reusable. |
