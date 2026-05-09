import ComposableArchitecture
import XCTest
@testable import FromInk

@MainActor
final class ToolbarFeatureTests: XCTestCase {

    // MARK: - Tool Selection

    func test_selectTool_switchesActive() async {
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
    }

    func test_selectTool_dismissesOpenPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .pen,
                openPanel: .toolCustomization(.pen)
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolSelected(.marker)) {
            $0.previousToolID = .pen
            $0.activeToolID = .marker
            $0.openPanel = nil
        }
    }

    // MARK: - Pencil Double-Tap

    func test_pencilDoubleTap_switchesToEraser() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .fountain),
            reducer: { ToolbarFeature() }
        )

        await store.send(.pencilDoubleTapped) {
            $0.previousToolID = .fountain
            $0.activeToolID = .eraser
        }
    }

    func test_pencilDoubleTap_restoresPreviousTool() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .eraser,
                previousToolID: .fountain
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.pencilDoubleTapped) {
            $0.activeToolID = .fountain
        }
    }

    // MARK: - Two-Finger Hold

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

    // MARK: - Panel Toggling

    func test_doubleTapTool_opensPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(activeToolID: .pen),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolDoubleTapped(.pen)) {
            $0.openPanel = .toolCustomization(.pen)
        }
    }

    func test_doubleTapTool_closesPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .pen,
                openPanel: .toolCustomization(.pen)
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolDoubleTapped(.pen)) {
            $0.openPanel = nil
        }
    }

    func test_doubleTapDifferentTool_switchesPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(
                activeToolID: .pen,
                openPanel: .toolCustomization(.pen)
            ),
            reducer: { ToolbarFeature() }
        )

        await store.send(.toolDoubleTapped(.marker)) {
            $0.activeToolID = .marker
            $0.openPanel = .toolCustomization(.marker)
        }
    }

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

    func test_boltNotVisibleBelow10Strokes() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )

        await store.send(.strokeCountUpdated(9))
        XCTAssertFalse(store.state.isBoltVisible)
    }

    func test_boltVisibleAt10Strokes() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )

        await store.send(.strokeCountUpdated(10))
        XCTAssertTrue(store.state.isBoltVisible)
    }

    // MARK: - Template Selection

    func test_templateSelected_updatesAndDismissesPanel() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(openPanel: .templatePicker),
            reducer: { ToolbarFeature() },
            withDependencies: {
                $0.userPreferences.saveTemplate = { _ in }
            }
        )

        await store.send(.templateSelected(.grid)) {
            $0.template = .grid
            $0.openPanel = nil
        }
    }

    // MARK: - Side Changed

    func test_sideChanged_persists() async {
        var savedSide: ToolbarSide?

        let store = TestStore(
            initialState: ToolbarFeature.State(side: .left),
            reducer: { ToolbarFeature() },
            withDependencies: {
                $0.userPreferences.saveToolbarSide = { side in
                    savedSide = side
                }
            }
        )

        await store.send(.sideChanged(.right)) {
            $0.side = .right
        }

        XCTAssertEqual(savedSide, .right)
    }

    // MARK: - Settings Persistence

    func test_toolSettingsChanged_persists() async {
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

    // MARK: - Lifecycle

    func test_onAppear_loadsSettings() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() },
            withDependencies: {
                $0.userPreferences.loadToolSettings = {
                    [ToolSettingsEntry(id: .pen, settings: PenSettings(penType: .fineliner))]
                }
                $0.userPreferences.loadToolbarSide = { .right }
                $0.userPreferences.loadActiveToolID = { .fountain }
                $0.userPreferences.loadTemplate = { .grid }
            }
        )

        await store.send(.onAppear)

        await store.receive(
            .settingsLoaded(LoadedSettings(
                toolSettings: [ToolSettingsEntry(id: .pen, settings: PenSettings(penType: .fineliner))],
                side: .right,
                activeToolID: .fountain,
                template: .grid
            ))
        ) {
            $0.toolSettings = [ToolSettingsEntry(id: .pen, settings: PenSettings(penType: .fineliner))]
            $0.side = .right
            $0.activeToolID = .fountain
            $0.template = .grid
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

    func test_pencilSqueezed_noStateChange() async {
        let store = TestStore(
            initialState: ToolbarFeature.State(),
            reducer: { ToolbarFeature() }
        )

        await store.send(.pencilSqueezed)
    }
}
