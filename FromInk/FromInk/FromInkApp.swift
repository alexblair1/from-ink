import ComposableArchitecture
import Dependencies
import SwiftUI
import SwiftData

@main
struct FromInkApp: App {
    @AppStorage("appearanceSetting") private var appearance: AppearanceSetting = .system

    private let container: AppDependencyContainer
    private let store: StoreOf<AppFeature>

    init() {
        let container = AppDependencyContainer.live()
        self.container = container
        // Single install path: `prepareDependencies` sets the process-wide
        // registry, and TCA's Store inherits from it. Calling
        // `withDependencies` on the Store as well would create two
        // parallel install paths that must stay in sync — drift between
        // them is a class of bug we'd rather not have. SwiftUI views
        // using `@Dependency(...)` also resolve through `prepareDependencies`.
        prepareDependencies { deps in
            container.install(into: &deps)
        }
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
        // Register background tasks before app finishes launching.
        container.backgroundTokenRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRootWiringView(store: store)
                .designSystem(.standard)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container.modelContainerForSwiftUI)
    }
}
