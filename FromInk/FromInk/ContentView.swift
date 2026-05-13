import SwiftUI

/// Legacy bootstrap view — replaced by AppRootWiringView.
/// Kept temporarily until Xcode project references are cleaned up.
///
struct ContentView: View {
    var body: some View {
        HomeFeatureView(initialBrief: nil)
    }
}
