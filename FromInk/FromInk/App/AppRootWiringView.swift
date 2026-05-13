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
                if let homeStore = store.scope(state: \.home, action: \.home) {
                    HomeWiringView(store: homeStore)
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
