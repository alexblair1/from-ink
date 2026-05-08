import SwiftUI

/// Subtle press feedback for home screen cards.
/// 80ms linear opacity dip — no springs, no scale.
///
struct HomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.linear(duration: 0.08), value: configuration.isPressed)
    }
}
