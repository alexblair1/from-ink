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
        var activeSettings: PenSettings = .default
        var toolStack: [ToolID] = []
        var toolSettings: IdentifiedArrayOf<ToolSettingsEntry> = []
        var openPanel: PanelKind? = nil
        var side: ToolbarSide = .left
        var isBoltVisible: Bool = false
        var isDispatchRequested: Bool = false
    }

    @CasePathable
    enum Action {
        // Tool interaction
        case toolTapped(ToolID)

        // Apple Pencil gestures (sent from CanvasWrapper.Coordinator via parent scope)
        case pencilDoubleTapped
        case pencilSqueezed
        case twoFingerHoldBegan
        case twoFingerHoldEnded

        // Settings
        case toolSettingsChanged(ToolID, PenSettings)

        // Panels
        case templatePickerToggled
        case settingsToggled
        case panelDismissed

        // Chrome
        case sideChanged(ToolbarSide)
        case boltVisibilityChanged(Bool)

        // Forwarded to parent (return .none here)
        case undoTapped
        case redoTapped
        case analyzeTapped
        case dispatchTapped
        case dispatchAcknowledged
        case templateSelected(CanvasTemplate)

        // Lifecycle
        case onAppear
        case settingsLoaded(LoadedSettings)
    }

    @Dependency(\.userPreferences) var preferences

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            // MARK: - Tool interaction

            case .toolTapped(let id) where id != state.activeToolID:
                state.toolStack = []
                state.activeToolID = id
                state.activeSettings = state.toolSettings[id: id]?.settings ?? .default
                state.openPanel = nil
                return .none

            case .toolTapped(let id):
                let canCustomize = ToolDescriptor.descriptor(for: id)?.hasCustomization ?? false
                guard canCustomize else { return .none }
                state.openPanel = state.openPanel == .toolCustomization(id) ? nil : .toolCustomization(id)
                return .none

            case .pencilDoubleTapped where state.activeToolID == .eraser:
                let restored = state.toolStack.popLast() ?? .pen
                state.activeToolID = restored
                state.activeSettings = state.toolSettings[id: restored]?.settings ?? .default
                return .none

            case .pencilDoubleTapped:
                state.toolStack.append(state.activeToolID)
                state.activeToolID = .eraser
                state.activeSettings = .default
                return .none

            case .pencilSqueezed:
                return .none

            case .twoFingerHoldBegan:
                state.toolStack.append(state.activeToolID)
                state.activeToolID = .lasso
                state.activeSettings = .default
                return .none

            case .twoFingerHoldEnded:
                let restored = state.toolStack.popLast() ?? .pen
                state.activeToolID = restored
                state.activeSettings = state.toolSettings[id: restored]?.settings ?? .default
                return .none

            // MARK: - Settings

            case .toolSettingsChanged(let id, let settings):
                state.toolSettings[id: id] = ToolSettingsEntry(id: id, settings: settings)
                if id == state.activeToolID {
                    state.activeSettings = settings
                }

                return .run { _ in
                    await preferences.saveToolSettings(id, settings)
                }

            // MARK: - Panels

            case .templatePickerToggled:
                state.openPanel = state.openPanel == .templatePicker ? nil : .templatePicker
                return .none

            case .settingsToggled:
                state.openPanel = state.openPanel == .canvasSettings ? nil : .canvasSettings
                return .none

            case .panelDismissed:
                state.openPanel = nil
                return .none

            // MARK: - Chrome

            case .sideChanged(let side):
                state.side = side
                return .run { _ in
                    await preferences.saveToolbarSide(side)
                }

            case .boltVisibilityChanged(let visible):
                state.isBoltVisible = visible
                return .none

            // MARK: - Forwarded to parent

            case .dispatchTapped:
                state.isDispatchRequested = true
                return .none

            case .dispatchAcknowledged:
                state.isDispatchRequested = false
                return .none

            case .undoTapped, .redoTapped, .analyzeTapped, .templateSelected:
                return .none

            // MARK: - Lifecycle

            case .onAppear:
                return .run { send in
                    let settings = await preferences.loadToolSettings()
                    let side = await preferences.loadToolbarSide()
                    let toolID = await preferences.loadActiveToolID()
                    await send(
                        .settingsLoaded(
                            LoadedSettings(
                                toolSettings: settings,
                                side: side,
                                activeToolID: toolID
                            )
                        )
                    )
                }

            case .settingsLoaded(let loaded):
                state.toolSettings = loaded.toolSettings
                state.side = loaded.side
                state.activeToolID = loaded.activeToolID
                state.activeSettings = loaded.toolSettings[id: loaded.activeToolID]?.settings ?? .default
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
}
