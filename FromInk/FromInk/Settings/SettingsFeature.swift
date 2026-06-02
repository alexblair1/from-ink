import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Settings")

/// TCA feature for the settings overlay.
///
/// State holds:
///   - `destination`: which sub-screen is presented (`nil` = root list).
///   - `appearance`: user's chosen color-scheme override.
///   - `handedness`: user's chosen handedness.
///
/// Effects:
///   - `.appeared` loads both preferences via `UserPreferences`.
///   - `.appearanceChanged` / `.handednessChanged` update state AND
///     persist via the dependency.
///
/// `.dismissTapped` is a **delegate** action — the reducer doesn't
/// handle it (returns `.none`); the parent feature intercepts it
/// (via `.settings(.presented(.dismissTapped))`) and clears its own
/// `@Presents var settings` optional, which SwiftUI's
/// `.sheet(item:)` translates into the dismissal animation.
/// Presentation state stays owned by the presenter, not the
/// presented feature.
///
struct SettingsFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var destination: SettingsDestination?
        var appearance: AppearanceSetting
        var handedness: Handedness
        /// Permissions child state. Always present so the scoped
        /// reducer can respond to its own actions; the view only
        /// renders it when `destination == .permissions`, but the
        /// reducer keeps state warm so a re-push doesn't trigger a
        /// re-prompt.
        var permissions: PermissionsFeature.State

        init(
            destination: SettingsDestination? = nil,
            appearance: AppearanceSetting = .system,
            handedness: Handedness = .right,
            permissions: PermissionsFeature.State = PermissionsFeature.State()
        ) {
            self.destination = destination
            self.appearance = appearance
            self.handedness = handedness
            self.permissions = permissions
        }
    }

    @CasePathable
    enum Action: Equatable {
        case appeared
        case preferencesLoaded(appearance: AppearanceSetting, handedness: Handedness)
        case destinationTapped(SettingsDestination)
        case backTapped
        case appearanceChanged(AppearanceSetting)
        case handednessChanged(Handedness)
        /// Delegate action — parent intercepts to close the overlay.
        /// SettingsFeature itself returns `.none`.
        case dismissTapped
        /// Permissions child actions. Composed via `Scope`. The parent
        /// handles destination navigation; the child handles its own
        /// state machine.
        case permissions(PermissionsFeature.Action)
    }

    @Dependency(\.userPreferences) var preferences

    var body: some Reducer<State, Action> {
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }
        Reduce { state, action in
            switch action {
            case .appeared:
                return .run { send in
                    let appearance = await preferences.loadAppearance()
                    let handedness = await preferences.loadHandedness()
                    await send(.preferencesLoaded(appearance: appearance, handedness: handedness))
                }
                .cancellable(id: "settingsPreferencesLoad", cancelInFlight: true)

            case .preferencesLoaded(let appearance, let handedness):
                state.appearance = appearance
                state.handedness = handedness
                return .none

            case .destinationTapped(let dest):
                state.destination = dest
                return .none

            case .backTapped:
                state.destination = nil
                return .none

            case .appearanceChanged(let appearance):
                state.appearance = appearance
                return .run { _ in
                    await preferences.saveAppearance(appearance)
                }

            case .handednessChanged(let handedness):
                state.handedness = handedness
                return .run { _ in
                    await preferences.saveHandedness(handedness)
                }

            case .dismissTapped:
                // Parent intercepts. Reducer is intentionally a no-op
                // here so presentation state stays owned by the
                // presenter (HomeFeature).
                return .none

            case .permissions:
                // Permissions child actions handled by the scoped
                // PermissionsFeature reducer above.
                return .none
            }
        }
    }
}
