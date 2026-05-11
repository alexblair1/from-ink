import ComposableArchitecture
import XCTest
@testable import FromInk

@MainActor
final class ToolbarFeatureTests: XCTestCase {

    // MARK: - Tool Tapped — Switch Tool

    func test_toolTapped_switchesTool() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .pen),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.marker)) {
            $0.activeToolID = .marker
        }
    }

    func test_toolTapped_dismissesOpenPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .pen,
                openPanel: .toolCustomization(.pen)
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.marker)) {
            $0.activeToolID = .marker
            $0.openPanel = nil
        }
    }

    // MARK: - Tool Tapped — Active Tool (Customization Toggle)

    func test_toolTapped_activeWithCustomization_opensPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .pen),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.pen)) {
            $0.openPanel = .toolCustomization(.pen)
        }
    }

    func test_toolTapped_activeWithCustomization_closesPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .pen,
                openPanel: .toolCustomization(.pen)
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.pen)) {
            $0.openPanel = nil
        }
    }

    func test_toolTapped_activeWithoutCustomization_noOp() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .eraser),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.eraser))
    }

    func test_toolTapped_lasso_activeNoOp() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .lasso),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.lasso))
    }

    // MARK: - Pencil Double-Tap

    func test_pencilDoubleTap_switchesToEraser() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .fountain),
            reducer: { ToolbarFeature() }
        )

        await store.send(.pencilDoubleTapped) {
            $0.toolStack = [.fountain]
            $0.activeToolID = .eraser
        }
    }

    func test_pencilDoubleTap_restoresPreviousTool() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .eraser,
                toolStack: [.fountain]
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.pencilDoubleTapped) {
            $0.toolStack = []
            $0.activeToolID = .fountain
        }
    }

    func test_pencilDoubleTap_restoresDefaultWhenStackEmpty() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .eraser),
            reducer: { ToolbarFeature() }
        )

        await store.send(.pencilDoubleTapped) {
            $0.activeToolID = .pen
        }
    }

    // MARK: - Two-Finger Hold

    func test_twoFingerHold_temporaryLasso() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .pen),
            reducer: { ToolbarFeature() }
        )

        await store.send(.twoFingerHoldBegan) {
            $0.toolStack = [.pen]
            $0.activeToolID = .lasso
        }

        await store.send(.twoFingerHoldEnded) {
            $0.toolStack = []
            $0.activeToolID = .pen
        }
    }

    func test_twoFingerHold_nestedWithPencilDoubleTap() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .pen),
            reducer: { ToolbarFeature() }
        )

        // Pencil double-tap → eraser
        await store.send(.pencilDoubleTapped) {
            $0.toolStack = [.pen]
            $0.activeToolID = .eraser
        }

        // Two-finger hold during eraser → lasso
        await store.send(.twoFingerHoldBegan) {
            $0.toolStack = [.pen, .eraser]
            $0.activeToolID = .lasso
        }

        // Release hold → back to eraser
        await store.send(.twoFingerHoldEnded) {
            $0.toolStack = [.pen]
            $0.activeToolID = .eraser
        }

        // Pencil double-tap again → back to pen
        await store.send(.pencilDoubleTapped) {
            $0.toolStack = []
            $0.activeToolID = .pen
        }
    }

    // MARK: - Tool Switch Clears Stack

    func test_toolTapped_clearsStack() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .eraser,
                toolStack: [.pen]
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolTapped(.marker)) {
            $0.toolStack = []
            $0.activeToolID = .marker
        }
    }

    // MARK: - Panels

    func test_templatePickerToggled() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )

        await store.send(.templatePickerToggled) {
            $0.openPanel = .templatePicker
        }

        await store.send(.templatePickerToggled) {
            $0.openPanel = nil
        }
    }

    func test_settingsToggled() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )

        await store.send(.settingsToggled) {
            $0.openPanel = .canvasSettings
        }

        await store.send(.settingsToggled) {
            $0.openPanel = nil
        }
    }

    func test_panelDismissed() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(openPanel: .canvasSettings),
            reducer: { ToolbarFeature() }
        )

        await store.send(.panelDismissed) {
            $0.openPanel = nil
        }
    }

    // MARK: - Bolt Visibility

    func test_boltVisibilityChanged() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )

        await store.send(.boltVisibilityChanged(true)) {
            $0.isBoltVisible = true
        }

        await store.send(.boltVisibilityChanged(false)) {
            $0.isBoltVisible = false
        }
    }

    // MARK: - Side Changed

    func test_sideChanged_persists() async {
        let savedSide = LockIsolated<ToolbarSide?>(nil)

        let store = TestStore(
            initialState: ToolbarFeature.State(side: .left),
            reducer: { ToolbarFeature() },
            withDependencies: {
                $0.userPreferences = UserPreferences(
                    loadToolSettings: { [] },
                    saveToolSettings: { _, _ in },
                    loadToolbarSide: { .left },
                    saveToolbarSide: { side in savedSide.setValue(side) },
                    loadActiveToolID: { ToolID(rawValue: "pen") },
                    saveActiveToolID: { _ in },
                    loadTemplate: { .none },
                    saveTemplate: { _ in }
                )
            }
        )

        await store.send(.sideChanged(.right)) {
            $0.side = .right
        }

        await store.finish()

        XCTAssertEqual(savedSide.value, .right)
    }

    // MARK: - Settings Persistence

    func test_toolSettingsChanged_persists() async {
        let savedID = LockIsolated<ToolID?>(nil)
        let savedSettings = LockIsolated<PenSettings?>(nil)

        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() },
            withDependencies: {
                $0.userPreferences = UserPreferences(
                    loadToolSettings: { [] },
                    saveToolSettings: { id, settings in
                        savedID.setValue(id)
                        savedSettings.setValue(settings)
                    },
                    loadToolbarSide: { .left },
                    saveToolbarSide: { _ in },
                    loadActiveToolID: { ToolID(rawValue: "pen") },
                    saveActiveToolID: { _ in },
                    loadTemplate: { .none },
                    saveTemplate: { _ in }
                )
            }
        )

        let newSettings = PenSettings(penType: .fineliner, thicknessIndex: 3)
        await store.send(.toolSettingsChanged(.pen, newSettings)) {
            $0.toolSettings[id: .pen] = ToolSettingsEntry(id: .pen, settings: newSettings)
            $0.activeSettings = newSettings
        }

        await store.finish()

        XCTAssertEqual(savedID.value, .pen)
        XCTAssertEqual(savedSettings.value, newSettings)
    }

    // MARK: - Lifecycle

    func test_onAppear_loadsSettings() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() },
            withDependencies: {
                $0.userPreferences = UserPreferences(
                    loadToolSettings: {
                        [ToolSettingsEntry(id: ToolID(rawValue: "pen"), settings: PenSettings(penType: .fineliner))]
                    },
                    saveToolSettings: { _, _ in },
                    loadToolbarSide: { .right },
                    saveToolbarSide: { _ in },
                    loadActiveToolID: { ToolID(rawValue: "fountain") },
                    saveActiveToolID: { _ in },
                    loadTemplate: { .none },
                    saveTemplate: { _ in }
                )
            }
        )
        
        await store.send(.onAppear)
        
        await store.receive(\.settingsLoaded) {
            $0.toolSettings = [ToolSettingsEntry(id: .pen, settings: PenSettings(penType: .fineliner))]
            $0.side = .right
            $0.activeToolID = ToolID(rawValue: "fountain")
            $0.activeSettings = .default // fountain has no saved settings, falls back to default
        }
    }

    // MARK: - Forwarded Actions

    func test_undoTapped_noStateChange() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )
        await store.send(.undoTapped)
    }

    func test_redoTapped_noStateChange() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )
        await store.send(.redoTapped)
    }

    func test_analyzeTapped_noStateChange() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )
        await store.send(.analyzeTapped)
    }

    func test_templateSelected_noStateChange() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )
        await store.send(.templateSelected(.grid))
    }

    func test_pencilSqueezed_noStateChange() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )
        await store.send(.pencilSqueezed)
    }
}
