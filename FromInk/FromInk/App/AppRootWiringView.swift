import ComposableArchitecture
import SwiftUI

/// Root wiring view. Switches on bootstrap phase:
/// - .launching: LaunchScreen
/// - .ready: HomeWiringView (scoped to HomeFeature)
/// - .failed: BootstrapFailureView with retry
///
/// The .task fires BootstrapFeature.start — the one allowed
/// bootstrap effect from a wiring view (EDD §13).
///
struct AppRootWiringView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        ZStack {
            switch store.bootstrap.phase {
            case .launching:
                LaunchScreen()
                    .transition(.opacity)

            case .ready:
                if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                    OnboardingWiringView(store: onboardingStore)
                        .transition(.opacity)
                } else if let homeStore = store.scope(state: \.home, action: \.home) {
                    HomeWiringView(store: homeStore)
                        .transition(.opacity)
                } else {
                    // Closes the gap between bootstrap reaching `.ready` and
                    // `AppFeature` finishing the `hasSeenOnboardingResolved`
                    // effect that seeds either `onboarding` or `home`.
                    // Without this fallback, `body` rendered nothing for one
                    // frame — visible as a brief paper flash before the
                    // first screen appeared.
                    LaunchScreen()
                        .transition(.opacity)
                }

            case .failed:
                BootstrapFailureView(
                    model: .init(
                        icon: "exclamationmark.triangle",
                        title: AppStrings.Bootstrap.unableToStart,
                        message: failureMessage(store.bootstrap.error),
                        retryLabel: AppStrings.Bootstrap.tryAgain,
                        onRetry: { store.send(.bootstrap(.retry)) }
                    )
                )
                .transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.12), value: store.bootstrap.phase)
        // Drives the onboarding → home crossfade. `store.bootstrap.phase`
        // doesn't change during this swap (it stays `.ready` throughout),
        // so a separate animation modifier keyed on the onboarding-presence
        // bool is required — otherwise SwiftUI hard-cuts between the two
        // wiring views and the transition's `.opacity` declaration above
        // never fires.
        .animation(.linear(duration: 0.18), value: store.onboarding == nil)
        .task { store.send(.bootstrap(.start)) }
    }

    private func failureMessage(_ error: BootstrapError?) -> String {
        switch error {
        case .storageUnavailable:
            return AppStrings.Bootstrap.storageError
        case .schemaMigrationFailed:
            return AppStrings.Bootstrap.migrationError
        case .none:
            return AppStrings.Bootstrap.unknownError
        }
    }
}
