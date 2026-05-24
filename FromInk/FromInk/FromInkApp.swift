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
        // Install dependencies process-wide so `@Dependency(...)` accesses
        // from SwiftUI views (not just TCA reducers) resolve to the live
        // implementations. Without this, raw views fall back to each
        // dependency's `liveValue` — and our `NotebookClient.liveValue`
        // is a safety stub that throws on every call.
        prepareDependencies { deps in
            container.install(into: &deps)
        }
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: { deps in
            container.install(into: &deps)
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
