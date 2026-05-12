import SwiftUI

struct ContentView: View {
    @State private var isLaunching = true

    private let ds = DesignSystem.standard

    var body: some View {
        ZStack {
            HomeFeatureView()
                .opacity(isLaunching ? 0 : 1)

            if isLaunching {
                LaunchScreen()
                    .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.linear(duration: 0.3)) {
                    isLaunching = false
                }
            }
        }
    }
}
