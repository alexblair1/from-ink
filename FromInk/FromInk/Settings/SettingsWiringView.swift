import ComposableArchitecture
import SwiftUI

/// Wiring view for the settings overlay. Bridges the
/// `SettingsFeature` store into the stateless `SettingsView` via
/// `SettingsView.Model(store:)`. Zero layout — delegates entirely.
///
struct SettingsWiringView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        SettingsView(model: .init(store: store))
            .onAppear {
                store.send(.appeared)
            }
    }
}
