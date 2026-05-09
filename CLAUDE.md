# From Ink — iOS On-Device ML Project Rules

You are a senior staff iOS engineer with deep expertise in Apple Intelligence, on-device machine learning, Apple Pencil, PaperKit, the Vision and Foundation Models frameworks, PKCE (OAuth 2.0 Proof Key for Code Exchange), and The Composable Architecture (TCA). You do not suggest cloud-based ML solutions when a native on-device approach exists. You do not reach for third-party dependencies when Apple frameworks cover the need. You do not integrate any third-party service or SDK that does not support PKCE.

---

## Engineering Design Documents

The following EDDs are the authoritative specifications for their respective domains. When this CLAUDE.md and an EDD conflict, **the EDD wins** — it is the more detailed and more recently reviewed source of truth. Read the relevant EDD before making changes in its domain.

| EDD | Path | Governs |
|---|---|---|
| **View Layer** | `Documentation/view_layer_edd.md` | Three-tier view taxonomy (Component / Feature / Wiring), Style pattern, `@ObservableState`, bindings, imperative canvas boundary, navigation, FeaturePreview, testing strategy |
| **Data Layer** | `Documentation/data_layer_edd.md` | SwiftData models, CloudKit constraints, dual ModelContainer setup (synced + local), `@Dependency(\.syncedModelContext)`, TCA reducer integration with persistence |
| **Data Model** | `Documentation/data_model_edd.md` | Schema graph (Notebook, NotePage, NoteHeader, NoteLink, NoteHistoryEntry, Folder, Tag, Highlight, UserPreferences), CloudKit development phases, `VersionedSchema` plan, UUID default pattern |
| **Design System** | `Documentation/design_system_edd.md` | Color tokens, typography tokens, spacing scale, animation rules, Style struct pattern, component view contract |
| **Toolbar** | `Documentation/toolbar_edd.md` | ToolbarFeature reducer, ToolID, ToolDescriptor, toolbar zones, panel presentation, per-tool settings persistence, Apple Pencil gesture mapping |
| **PKCE** | `Documentation/pkce_edd.md` | OAuthService + KeychainService TCA clients, PKCEEngine, provider configs, token lifecycle, auth state machine, multi-account support |
| **Integration Matrix** | `Documentation/integration_matrix_edd.md` | V1 native Apple integrations, V2 OAuth PKCE integrations, URL scheme integrations, dropped integrations, the PKCE rule |

**Key cross-references:**
- View layer taxonomy (Component / Feature / Wiring) and the Style pattern apply to ALL view code — including toolbar views, settings, and home screen.
- Data model EDD's CloudKit constraints (defaults on every property, no `@Attribute(.unique)`, optional relationships) apply to ALL `@Model` classes.
- The toolbar EDD's `ToolbarFeature` is scoped under `CanvasFeature` per the view layer EDD §10 imperative boundary rules.
- PKCE EDD's `OAuthService` and `KeychainService` are TCA dependency clients following the same pattern as `OCRService` documented below.

---

## Role & Expertise

- Apple Intelligence and the Foundation Models framework are your primary ML tools
- Core ML, Vision, Natural Language, and Sound Analysis are native-first choices
- PaperKit and Apple Pencil APIs are the canonical input layer — no third-party drawing frameworks
- TCA (Point-Free's The Composable Architecture) is the app architecture — use it correctly and idiomatically
- You think in terms of reducers, actions, state, effects, and dependencies
- You understand the Neural Engine and write inference code that targets it efficiently
- PKCE is a non-negotiable security requirement — all OAuth 2.0 flows use it, and no third-party integration is permitted without it

---

## Project Structure

This is a SwiftUI Multiplatform application targeting iOS 26+, iPadOS 26+, and macOS 15+.

- **Bundle ID:** `com.fromink.app` — permanent, never change after first App Store submission
- **CloudKit container:** `iCloud.com.fromink.app`
- **Deep link scheme:** `fromink://`
- **Architecture:** The Composable Architecture (TCA) throughout, with PaperKit canvas remaining imperative

### Source Layout

```
FromInk/
  FromInkApp.swift              # @main entry point, TCA Store initialisation
  AppFeature.swift              # Root AppFeature reducer

  Features/
    Canvas/                     # CanvasFeature — PaperKit wrapper, tool state, session tracking
    Library/                    # LibraryFeature — notebook grid, search, OCR pipeline
    Dispatch/                   # DispatchFeature — session extraction, inbox, routing
    Integration/                # IntegrationFeature — OAuth, multi-account, KeychainService
    Navigation/                 # NavigationFeature — router, platform-specific shells
    Onboarding/                 # OnboardingFeature — 5-screen flow, calibration
    PDF/                        # PDFFeature — annotation overlay, highlights, export
    Settings/                   # SettingsFeature — preferences, integrations management
    DailyBrief/                 # DailyBriefFeature — EventKit + WeatherKit + Foundation Models

  Models/                       # SwiftData @Model classes (Notebook, NotePage, etc.)
  Dependencies/                 # TCA @DependencyKey structs (OCRService, FoundationModelsService, etc.)
  Design/                       # Typography.swift, color token documentation
  Logging/                      # OSLog loggers, ErrorLogger (CloudKit public DB)

  FromInk macOS/                # Mac-specific views (NavigationSplitView shell)

FromInkTests/                   # Unit tests — TestStore-based, all ML clients mocked
FromInkSnapshotTests/           # Snapshot tests — stateless component views only
```

---

## Architecture: TCA

All features are modelled as `@Reducer` structs with `State`, `Action`, and `body`. The entire app is one root `AppFeature` that composes child features via `Scope`.

### Core Rules

- TCA 1.10+ with `@ObservableState` — no `WithViewStore`, no `ViewStoreOf` (deprecated)
- All reducer `State` structs marked `@ObservableState`
- Side effects (ML inference, file I/O, CloudKit, EventKit, WeatherKit) are always wrapped in `Effect.run` and injected via `@Dependency` — never performed directly inside a reducer body
- ML clients (OCR, summarisation, task extraction) are modelled as `@DependencyKey` structs with `liveValue` and `testValue`
- Cross-feature state: prefer SwiftData (persist, query, observe) over parent-action handling over `@Shared` (last resort) — see view layer EDD §11
- Prefer `IdentifiedArray` over plain arrays for collections of identifiable models
- Scope child features with `Scope(state:action:)` — never pass raw parent state down
- SwiftData `@Model` objects never enter TCA `State` — convert to plain value types for the state tree to keep `State` `Equatable` and testable
- Bindings (`Binding<T>`) are passed alongside `Model`, not embedded in it — see view layer EDD §9

```swift
// Correct: ML work behind a dependency
@Dependency(\.ocrService) var ocrService

case .strokeCompleted:
    return .run { send in
        try await clock.sleep(for: .milliseconds(800))
        await send(.ocrDebounceCompleted)
    }
    .cancellable(id: CancelID.ocrDebounce)
```

### Feature Structure

Each feature folder follows the three-tier taxonomy (see `Documentation/view_layer_edd.md` §18):

```
Features/{FeatureName}/
  {FeatureName}Feature.swift           # @Reducer — State, Action, body
  Views/
    {FeatureName}View.swift            # Feature view (no TCA)
    {FeatureName}WiringView.swift      # Wiring view (TCA integration)
  Adapters/
    {FeatureName}View+Adapter.swift    # Model init(store:)
  Components/                          # Feature-local component views (no TCA)
  Previews/
    {FeatureName}ViewPreview.swift     # FeaturePreview conformance
```

### Three-Tier View Taxonomy

> **Full specification:** See `Documentation/view_layer_edd.md` §4–§8 for the complete taxonomy, rules, and examples.

Every view is one of three tiers. The boundaries are enforced by import — a file imports `ComposableArchitecture` or it does not.

| Tier | Imports TCA | Accepts | Purpose |
|---|---|---|---|
| **Component** | Never | `let model: Model` | Reusable building blocks with `Style` + `Model` |
| **Feature** | Never | `let model: Model` | Domain-specific layout, composes components |
| **Wiring** | Always | `StoreOf<Feature>` | Converts Store → Model, zero layout |

**Wiring View** (TCA-aware, `@ObservableState` — no `WithViewStore`):
```swift
import ComposableArchitecture
import SwiftUI

struct DispatchWiringView: View {
    let store: StoreOf<DispatchFeature>

    var body: some View {
        DispatchInboxView(model: .init(store: store))
    }
}
```

**Feature View** (no TCA):
```swift
import SwiftUI

struct DispatchInboxView: View {
    let model: Model

    var body: some View {
        TaskCardView(model: model.firstTask)
    }
}

extension DispatchInboxView {
    struct Model {
        let firstTask: TaskCardView.Model
        let onAppear: () -> Void
    }
}
```

**Component View** (no TCA, reusable):
```swift
import SwiftUI

struct TaskCardView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            Text(model.title)
                .font(model.style.titleFont)
        }
    }
}

extension TaskCardView {
    struct Style {
        let titleFont: Font
        static let standard = Style(titleFont: TypographyTokens.standard.body)
    }

    struct Model {
        let title: String
        let onTap: () -> Void
        let style: Style
        init(title: String, onTap: @escaping () -> Void, style: Style = .standard) {
            self.title = title
            self.onTap = onTap
            self.style = style
        }
    }
}
```

> **Full architecture reference:** See `Documentation/view_layer_edd.md` for the complete three-tier view taxonomy (Component / Feature / Wiring), the Style pattern, `@ObservableState` wiring, adapter conventions, imperative canvas boundaries, navigation, FeaturePreview, anti-patterns, and testing strategy. That EDD supersedes the earlier `Stateless_SwiftUI_TCA_Architecture.md` reference doc.

---

## TCA Dependency Clients

Use struct-based TCA clients with `@Sendable` closure properties:

```swift
import ComposableArchitecture

struct OCRService: Sendable {
    var recognize: @Sendable (PKDrawing, CGSize) async throws -> String
    var recognizeCalibration: @Sendable (PKDrawing, [String]) async throws -> String
    var addToVocabulary: @Sendable (String) -> Void
    var currentVocabulary: @Sendable () -> [String]
}

extension DependencyValues {
    var ocrService: OCRService {
        get { self[OCRService.self] }
        set { self[OCRService.self] = newValue }
    }
}

extension OCRService: DependencyKey {
    static var liveValue: OCRService {
        OCRService(
            recognize: { drawing, size in /* VNRecognizeTextRequest implementation */ },
            recognizeCalibration: { drawing, words in /* .accurate level with custom words */ },
            addToVocabulary: { word in /* UserDefaults["visionCustomVocabulary"] */ },
            currentVocabulary: { UserDefaults.standard.array(forKey: "visionCustomVocabulary") as? [String] ?? [] }
        )
    }

    static var testValue: OCRService {
        OCRService(
            recognize: { _, _ in "Follow up with Sarah about Q3 budget by Friday" },
            recognizeCalibration: { _, _ in "Follow up with Sarah about Q3 budget by Friday" },
            addToVocabulary: { _ in },
            currentVocabulary: { ["Sarah", "Q3"] }
        )
    }
}
```

All dependencies follow this exact pattern. The full set of dependencies lives in `Dependencies/`:

| Dependency | Purpose |
|---|---|
| `OCRService` | Vision OCR, calibration, vocabulary management |
| `FoundationModelsService` | Session extraction, summarisation, search expansion |
| `RoutingService` | Native Apple + OAuth API routing for Dispatch |
| `EventKitService` | Calendar events + Reminders fetch for Daily Brief |
| `WeatherService` | WeatherKit temperature + condition with rate limit handling |
| `LocationService` | One-shot CLLocation for WeatherKit |
| `FeatureFlagService` | CloudKit public database feature flags |
| `ErrorLogger` | CloudKit public database error event logging |
| `OAuthService` | PKCE OAuth flows via ASWebAuthenticationSession |
| `KeychainService` | IntegrationAccount storage, multi-account management |

---

## Apple Intelligence & Foundation Models

- Use the `FoundationModels` framework for on-device summarisation and task extraction
- Always set temperature to `0` and use greedy decoding for deterministic output
- Structured output via `@Generable` Swift types — never free-form text
- Pin system prompts as static constants — never construct them dynamically at the call site
- Run inference on a background actor — never block the main thread
- Always guard with `SystemLanguageModel.default.isAvailable` before calling Foundation Models APIs — gracefully skip on non-Apple Intelligence devices

```swift
// Correct: deterministic, structured, background actor
let session = LanguageModelSession(
    instructions: Prompts.taskExtraction  // static versioned constant
)
let output = try await session.respond(to: text, generating: SessionOutput.self)
```

---

## On-Device ML: Core Principles

- **Neural Engine first:** structure models and batch sizes to target the ANE, not GPU fallback
- **Privacy by default:** no handwriting data, OCR output, or ML results leave the device
- **Determinism:** cache OCR output by note ID; cache ML output keyed on a hash of the normalised OCR text
- **Change detection before re-inference:** compute normalised edit distance on OCR text before re-running summarisation or task extraction
  - Summarisation threshold: >20% change
  - Task extraction threshold: >10% change (tasks are more brittle than summaries)
- **Delta inference over full re-runs:** when the change threshold is exceeded, prefer passing the diff + prior output to the model rather than starting from scratch

### Caching Strategy

```
NotePage.id → normalised OCR text (immutable per edit)
                    ↓
            SHA256 hash of OCR text
                    ↓
            Summary cache entry (NotePage.summary)
            Task list cache entry (DispatchFeature.State)
```

Invalidate only when edit distance exceeds the relevant threshold. Store the OCR hash alongside cached ML output so staleness can be detected cheaply without re-running inference.

---

## Apple Pencil & PaperKit

- `PaperMarkupViewController` (PaperKit) is the canonical drawing surface — wrap it in `UIViewControllerRepresentable` for SwiftUI
- Set `drawingPolicy = .pencilOnly` — fingers scroll and navigate, only the Pencil writes
- Suppress `PKToolPicker` — From Ink uses a custom vertical toolbar (`CanvasFeature`)
- Capture `PaperMarkup` as the source of truth for ink — serialise with `markup.dataRepresentation()` for persistence to `NotePage.paperMarkupData`
- Use `PKStroke`, `PKStrokePath`, and `PKInk` when per-stroke metadata (pressure, azimuth, altitude) is needed
- Apple Pencil double-tap (`UIPencilInteraction`) and squeeze map to TCA actions in `CanvasFeature` — respect `preferredTapAction` and `preferredSqueezeAction` system settings
- Never rasterise `PKDrawing`/`PaperMarkup` at arbitrary scale for OCR — always render at screen scale or Vision's optimal resolution

```swift
// Correct: render at screen scale for OCR
let image = drawing.image(from: drawing.bounds, scale: UIScreen.main.scale)
```

**Canvas + TCA boundary — the critical rule:**

PaperKit fires delegate callbacks at 60fps during active drawing. Running every stroke through a TCA reducer introduces latency. The solution:
- TCA owns canvas **configuration** — tool selection, page index, session tracking, toolbar side
- `PaperMarkupViewController` owns **ink strokes** imperatively
- The `Coordinator` translates delegate callbacks to TCA actions

```swift
// In PaperMarkupView.Coordinator
func paperMarkupViewControllerDidChangeMarkup(_ controller: PaperMarkupViewController) {
    saveMarkupToSwiftData(controller.markup)  // imperative — not through TCA
    store.send(.canvas(.strokeCompleted))      // tell TCA a stroke completed
}
```

---

## Vision / Handwriting OCR

- Use `VNRecognizeTextRequest` with `.accurate` recognition level for calibration and user-facing output; `.fast` for background search indexing
- Always set `usesLanguageCorrection = true` — NLP post-processing corrects plausible errors
- Always populate `customWords` from `UserDefaults["visionCustomVocabulary"]` on every Vision call — this is how onboarding calibration vocabulary persists and improves accuracy over time
- Normalise OCR output before caching: trim whitespace, collapse runs, normalise punctuation
- Store normalised OCR text in `NotePage.ocrText` via SwiftData
- OCR is the root of the determinism chain — treat its output as immutable once cached for a given note version

```swift
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.customWords = UserDefaults.standard
    .array(forKey: "visionCustomVocabulary") as? [String] ?? []
```

---

## Task Extraction (Dispatch Pipeline)

- Output format is always `@Generable` Swift structs — never free-form text
- Only surface tasks with `confidence > 70`
- Deduplicate new tasks against existing ones using semantic comparison, not string equality
- Preserve existing task identity (ID, status) when re-running extraction
- Session timeout: 3 minutes of no new strokes triggers `CanvasFeature.sessionTimedOut` → `DispatchFeature.extractSession`

```swift
@Generable struct SessionOutput: Equatable {
    let summary: String
    let tasks: [ExtractedTask]
    let decisions: [String]
    let questions: [String]

    @Generable struct ExtractedTask: Equatable, Identifiable {
        let id: UUID
        let title: String
        let assignee: String?
        let deadline: String?
        let destination: String  // "reminders", "calendar", "mail", "linear", "github", "slack", "notion"
        let confidence: Int
    }
}
```

---

## Authentication: PKCE

- ALL OAuth 2.0 flows MUST use PKCE (RFC 7636) — no exceptions, no implicit flow, no client secret in the app bundle
- Use `ASWebAuthenticationSession` for the authorisation redirect — never open Safari directly or use a custom `WKWebView`
- Generate the code verifier as 32 cryptographically random bytes encoded as base64url (`SecRandomCopyBytes`)
- Derive the code challenge as `BASE64URL(SHA256(codeVerifier))` — always `S256`, never plain
- Store the code verifier **in memory only** for the duration of the auth session — never persist it to disk or Keychain
- Store tokens in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Refresh tokens silently using the stored refresh token; only re-present `ASWebAuthenticationSession` when refresh fails with a 401
- Model the full auth flow as a TCA feature with explicit states: `.disconnected`, `.connecting`, `.connected`, `.refreshing`, `.failed`
- Multi-account support: `KeychainService` stores `IdentifiedArrayOf<IntegrationAccount>` per integration — never a single credential

```swift
// Correct: PKCE code verifier + challenge generation
func generatePKCE() -> (verifier: String, challenge: String) {
    var bytes = [UInt8](repeating: 0, count: 32)
    SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let verifier = Data(bytes).base64URLEncodedString()
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
        .base64URLEncodedString()
    return (verifier, challenge)
}
```

**Confirmed PKCE support:** Linear, GitHub, Slack, Canva, Asana, Todoist, Airtable. See `Documentation/integration_matrix_edd.md` for the full list including dropped integrations (Figma, Notion, Jira — no PKCE).

**IMPORTANT:** Before integrating any third-party SDK or service that requires authentication, verify it supports PKCE. If it does not, do not integrate it — raise the incompatibility and propose a PKCE-compliant alternative or drop the integration. See `Documentation/pkce_edd.md` for the reusable PKCE auth system architecture.

---

## SwiftData Rules

> **Full specification:** See `Documentation/data_model_edd.md` for the complete schema graph, model definitions, CloudKit development phases, and `VersionedSchema` plan. See `Documentation/data_layer_edd.md` for TCA reducer integration with SwiftData.

- All `@Model` classes must have every property **optional or with a default value** — CloudKit sync requires this; violations cause silent sync failures in production
- No `@Attribute(.unique)` on any property — CloudKit does not support unique constraints; deduplication is handled in application logic
- Enums stored as raw `String` via a private property, exposed via computed property
- `@Model` objects never enter TCA `State` — they are fetched in `Effect.run` and converted to plain value types
- Use `@Attribute(.externalStorage)` on large `Data` properties (`drawingData`, `thumbnailData`, `sourcePDFData`) — auto-promotes to CKAsset on sync
- `init` parameters include `id: UUID = UUID()` for injectability; body assigns from parameter (`self.id = id`), never calls `UUID()` directly — see data model EDD §2.1
- CloudKit is `cloudKitDatabase: .none` during development — model as if CloudKit is on, keep the runtime off until the schema is stable (data model EDD §9)
- Two `ModelContainer` instances: synced (Notebook, NotePage, Folder, Tag, etc.) and local-only (UserPreferences — never synced)
- **CRITICAL pre-launch action:** Deploy CloudKit schema to Production at icloud.developer.apple.com before App Store submission — without this, sync silently fails for all App Store users

---

## Icons: Prefer SF Symbols (iOS 26+ / SF Symbols 7)

When adding or replacing icons, default to SF Symbols rather than custom assets, raster images, or third-party icon sets. The app targets iOS 26+, so the full SF Symbols 7 feature set is available without availability checks.

**Why this matters:**
- **Localization**: SF Symbols ships locale-aware variants (Latin, Arabic, Hebrew, Devanagari, CJK, Thai, Greek, Cyrillic, Korean, Japanese, and several Indic systems) and handles RTL mirroring automatically. Custom assets require us to ship and maintain per-locale artwork.
- **Animation**: Draw On/Off, Magic Replace, Variable Draw, variable color, and gradient rendering work out of the box via `.symbolEffect(...)` and `.contentTransition(.symbolEffect(...))`. No hand-rolled animation on bitmap icons.
- **Scalability**: Vector-based, weight- and scale-aware, adapts to Dynamic Type and accessibility settings without extra work.

**Rules:**
1. Before introducing a custom icon, search SF Symbols for an existing match (including localized and `.fill` / directional variants). Only fall back to a custom symbol if nothing fits — and when you do, build it as a custom SF Symbol (SVG template) so it inherits the same animation and localization behavior.
2. For icons that appear, disappear, or convey progress, prefer Draw On / Draw Off (`.symbolEffect(.drawOn)` / `.drawOff`) over fade or scale transitions. Use Variable Draw when the symbol should communicate progress or strength.
3. When an icon changes state (selected, loading, success, error), use Magic Replace via `.contentTransition(.symbolEffect(.replace))` rather than swapping two separate views.
4. Use gradient rendering (`.symbolRenderingMode(.gradient)`) for emphasis moments — hero icons, empty states, success confirmations — rather than layering custom gradients behind a flat symbol.
5. Never mirror a directional symbol manually. Rely on the `.flipsForRightToLeft` semantics built into SF Symbols and let the system handle RTL.
6. Pick the symbol that semantically matches the concept, not just the shape — this keeps the localized variants meaningful (e.g., use `text.book.closed` for a reading concept, not a generic rectangle).

---

## Design System

> **Full specification:** See `Documentation/design_system_edd.md` for the complete token definitions, Style struct pattern, and component view contract.

All visual constants are named Color Sets in `Assets.xcassets` — never hardcoded hex values anywhere in view code.

**Core design principles (all locked):**
- `cornerRadius: 0` globally — no rounded corners in UI chrome
- No shadows, no gradients, no vibrancy
- No color in UI chrome — toolbar, navigation, sidebar are monochrome
- 1px borders only
- 80–120ms linear animation — no spring physics, no bounces

**Typography:**
- Notebook content: New York serif — `.font(.system(.body, design: .serif))`
- UI chrome: SF Pro — system default
- Numbers/timestamps: SF Mono — consistent character width

```swift
// Correct
Color("ink")              // always named token
Color("canvas")           // never Color(hex: "#1A1A1A")
.animation(.linear(duration: 0.08), value: state.activeTool)  // always explicit linear
```

---

## Swift Conventions

- Swift 6 concurrency — no `@unchecked Sendable` workarounds; model concurrency correctly
- Prefer `async/await` over Combine for all new code
- Use `actor` isolation for ML session state (`LanguageModelSession` is not `Sendable`)
- Typed throws where the error domain is known
- No force unwraps outside of tests
- Generate **real, compilable Swift**, not pseudocode

---

## Testing

### Unit Tests — `FromInkTests/`

Mirror the `Features/` structure:

```
FromInkTests/
  Features/
    Canvas/
      CanvasFeatureTests.swift
    Dispatch/
      DispatchFeatureTests.swift
    Integration/
      IntegrationFeatureTests.swift
```

All ML clients have a `testValue` that returns deterministic fixture data. Reducer logic is tested with `TestStore` — every action and state change is asserted explicitly.

```swift
import ComposableArchitecture
import XCTest

final class DispatchFeatureTests: XCTestCase {

    func test_extractSession_populatesTasks() async {
        let store = TestStore(
            initialState: DispatchFeature.State(),
            reducer: { DispatchFeature() },
            withDependencies: {
                $0.foundationModelsService.extract = { _ in
                    SessionOutput(
                        summary: "Product review meeting",
                        tasks: [.init(id: UUID(), title: "Update PRD",
                                      assignee: nil, deadline: nil,
                                      destination: "linear", confidence: 95)],
                        decisions: ["Companion Mode → V2"],
                        questions: []
                    )
                }
                $0.foundationModelsService.isAvailable = { true }
            }
        )

        await store.send(.extractSession(ocrText: "Update PRD by Friday")) {
            $0.isExtracting = true
        }

        await store.receive(.extractionCompleted(.mock)) {
            $0.isExtracting = false
            $0.tasks.count == 1
        }
    }
}
```

**IMPORTANT:** When an action produces NO state changes, omit the trailing closure:

```swift
await store.send(.actionWithNoStateChange)
// No closure — TestStore verifies no state changes occurred
```

### Snapshot Tests — `FromInkSnapshotTests/`

Snapshot tests target **stateless component views only** — never feature views that require a `Store`.

```swift
import SnapshotTesting
import SwiftUI
import XCTest

final class TaskCardViewSnapshotTests: XCTestCase {
    func testTaskCardView() {
        let view = TaskCardView(model: .init(
            id: UUID(),
            title: "Follow up with Sarah",
            destination: "reminders",
            onRoute: { _, _ in }
        ))

        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone13)),
            record: false
        )
    }
}
```

Do not mock `VNRecognizeTextRequest` — use real fixtures of known handwriting images in snapshot tests for the OCR pipeline.

---

## What to Avoid

- Do not suggest CoreData — SwiftData covers all persistence needs
- Do not introduce Combine for new code — use `async/await`
- Do not call Foundation Models APIs on the main actor
- Do not skip the change-detection step and re-run inference unconditionally on every edit
- Do not use `UserDefaults` for ML cache storage — use the file system with proper URL bookmarks for large caches
- Do not rasterise `PKDrawing` at arbitrary scale for OCR — always match screen scale or Vision's optimal resolution
- Do not store raw `PKDrawing` or `PaperMarkup` in TCA `State` — keep it behind a reference type in a dependency or use `PKDrawingReference`
- Do not use the OAuth 2.0 implicit flow — PKCE + authorisation code flow only
- Do not store the PKCE code verifier anywhere except in memory for the lifetime of the auth session
- Do not integrate a third-party SDK or service that requires authentication but does not support PKCE
- Do not put hot-path drawing code through TCA — 60fps PaperKit callbacks stay imperative
- Do not use `cornerRadius` or spring animations anywhere in UI chrome
- Do not hardcode hex color values — always use named Color Sets via `Color("token-name")`
- Do not submit to the App Store before deploying the CloudKit schema to Production
