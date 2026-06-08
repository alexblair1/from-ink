import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `SettingsFeature` — the TCA-driven settings
/// overlay. Pins the load-on-appear effect, the
/// destination-navigation state machine, the appearance/handedness
/// persistence side effects, and the delegate-`dismissTapped`
/// contract (the reducer does NOT close itself; the parent does).
///
final class SettingsFeatureTests: XCTestCase {

    // MARK: - .appeared

    @MainActor
    func test_appeared_loadsPreferences() async {
        let store = TestStore(
            initialState: SettingsFeature.State()
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.userPreferences = UserPreferences(
                loadToolSettings: { [] },
                saveToolSettings: { _, _ in },
                loadToolbarSide: { .left },
                saveToolbarSide: { _ in },
                loadActiveToolID: { ToolID(rawValue: "pen") },
                saveActiveToolID: { _ in },
                loadTemplate: { .none },
                saveTemplate: { _ in },
                loadAppearance: { .dark },
                saveAppearance: { _ in },
                loadHandedness: { .left },
                saveHandedness: { _ in },
                loadHasSeenOnboarding: { true },
                markOnboardingCompleted: { },
                loadOnboardingStep: { nil },
                saveOnboardingStep: { _ in }
            )
        }

        await store.send(.appeared)

        await store.receive(.preferencesLoaded(appearance: .dark, handedness: .left)) {
            $0.appearance = .dark
            $0.handedness = .left
        }
    }

    // MARK: - Navigation

    @MainActor
    func test_destinationTapped_setsDestination() async {
        let store = TestStore(
            initialState: SettingsFeature.State()
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.userPreferences = .testValue
        }

        await store.send(.destinationTapped(.handedness)) {
            $0.destination = .handedness
        }
    }

    @MainActor
    func test_backTapped_clearsDestination() async {
        var seeded = SettingsFeature.State()
        seeded.destination = .permissions

        let store = TestStore(initialState: seeded) {
            SettingsFeature()
        } withDependencies: {
            $0.userPreferences = .testValue
        }

        await store.send(.backTapped) {
            $0.destination = nil
        }
    }

    // MARK: - Appearance + handedness changes persist

    @MainActor
    func test_appearanceChanged_updatesStateAndPersists() async {
        let savedAppearance = LockIsolated<AppearanceSetting?>(nil)

        let store = TestStore(
            initialState: SettingsFeature.State(appearance: .system)
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.userPreferences = UserPreferences(
                loadToolSettings: { [] },
                saveToolSettings: { _, _ in },
                loadToolbarSide: { .left },
                saveToolbarSide: { _ in },
                loadActiveToolID: { ToolID(rawValue: "pen") },
                saveActiveToolID: { _ in },
                loadTemplate: { .none },
                saveTemplate: { _ in },
                loadAppearance: { .system },
                saveAppearance: { setting in
                    savedAppearance.setValue(setting)
                },
                loadHandedness: { .right },
                saveHandedness: { _ in },
                loadHasSeenOnboarding: { true },
                markOnboardingCompleted: { },
                loadOnboardingStep: { nil },
                saveOnboardingStep: { _ in }
            )
        }

        await store.send(.appearanceChanged(.dark)) {
            $0.appearance = .dark
        }
        await store.finish()

        XCTAssertEqual(
            savedAppearance.value, .dark,
            "appearanceChanged must persist the new value via UserPreferences"
        )
    }

    @MainActor
    func test_handednessChanged_updatesStateAndPersists() async {
        let savedHandedness = LockIsolated<Handedness?>(nil)

        let store = TestStore(
            initialState: SettingsFeature.State(handedness: .right)
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.userPreferences = UserPreferences(
                loadToolSettings: { [] },
                saveToolSettings: { _, _ in },
                loadToolbarSide: { .left },
                saveToolbarSide: { _ in },
                loadActiveToolID: { ToolID(rawValue: "pen") },
                saveActiveToolID: { _ in },
                loadTemplate: { .none },
                saveTemplate: { _ in },
                loadAppearance: { .system },
                saveAppearance: { _ in },
                loadHandedness: { .right },
                saveHandedness: { handedness in
                    savedHandedness.setValue(handedness)
                },
                loadHasSeenOnboarding: { true },
                markOnboardingCompleted: { },
                loadOnboardingStep: { nil },
                saveOnboardingStep: { _ in }
            )
        }

        await store.send(.handednessChanged(.left)) {
            $0.handedness = .left
        }
        await store.finish()

        XCTAssertEqual(
            savedHandedness.value, .left,
            "handednessChanged must persist the new value via UserPreferences"
        )
    }

    // MARK: - Delegate dismissTapped is a no-op in the reducer

    @MainActor
    func test_dismissTapped_isNoOpInReducer() async {
        // The parent (HomeFeature) intercepts `.dismissTapped` to
        // flip its own `isSettingsOpen` flag. The SettingsFeature
        // reducer itself must not mutate state for this action —
        // verified by the missing trailing closure on `.send`.
        let store = TestStore(
            initialState: SettingsFeature.State(
                destination: .appearance,
                appearance: .dark,
                handedness: .left
            )
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.userPreferences = .testValue
        }

        await store.send(.dismissTapped)
    }
}
