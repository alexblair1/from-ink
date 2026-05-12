import SwiftUI

/// Launch screen — "From Ink" wordmark centered on paper.
/// Matches the system launch screen background color (ink/Paper).
///
struct LaunchScreen: View {
    private let ds = DesignSystem.standard

    var body: some View {
        ZStack {
            ds.colors.paper
                .ignoresSafeArea()

            Text(AppStrings.Home.title)
                .font(.system(size: 24, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(ds.colors.ink)
                .tracking(0.4)
        }
    }
}

#Preview {
    LaunchScreen()
}
