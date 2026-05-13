import ComposableArchitecture
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
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: { deps in
            container.install(into: &deps)
        }
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
