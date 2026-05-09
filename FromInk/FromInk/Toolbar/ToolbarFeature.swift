import ComposableArchitecture
import Foundation

// Manually conforms to Reducer instead of using @Reducer macro.
// @Reducer resolves `ReducerOf<Self>` during macro expansion. With
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor this creates a circular
// reference the compiler cannot resolve. Explicit conformance breaks the loop.
// See DailyBriefFeature.swift for the same pattern.

struct ToolbarFeature: Reducer {

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
        // Tool selection (sent from ToolbarWiringView)
        case toolSelected(ToolID)
        case toolDoubleTapped(ToolID)

        // Apple Pencil gestures (sent from CanvasWrapper.Coordinator via parent scope)
        case pencilDoubleTapped
        case pencilSqueezed
        case twoFingerHoldBegan
        case twoFingerHoldEnded

        // Settings
        case toolSettingsChanged(ToolID, PenSettings)

        // Panels
        case toolCustomizationToggled(ToolID)
        case templatePickerToggled
        case settingsToggled
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
        case settingsLoaded(LoadedSettings)
    }

    @Dependency(\.userPreferences) var preferences

    var body: some Reducer<State, Action> {
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
                return .none

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

            case .toolCustomizationToggled(let id):
                if state.openPanel == .toolCustomization(id) {
                    state.openPanel = nil
                } else {
                    state.openPanel = .toolCustomization(id)
                }
                return .none

            case .templatePickerToggled:
                state.openPanel = state.openPanel == .templatePicker ? nil : .templatePicker
                return .none

            case .settingsToggled:
                state.openPanel = state.openPanel == .canvasSettings ? nil : .canvasSettings
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
                    await send(.settingsLoaded(LoadedSettings(
                        toolSettings: settings,
                        side: side,
                        activeToolID: toolID,
                        template: template
                    )))
                }

            case .settingsLoaded(let loaded):
                state.toolSettings = loaded.toolSettings
                state.side = loaded.side
                state.activeToolID = loaded.activeToolID
                state.template = loaded.template
                return .none
            }
        }
    }
}

// MARK: - Payload wrapper

struct LoadedSettings: Equatable, Sendable {
    let toolSettings: IdentifiedArrayOf<ToolSettingsEntry>
    let side: ToolbarSide
    let activeToolID: ToolID
    let template: CanvasTemplate
}
