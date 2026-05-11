import SwiftUI

/// Editorial press style for dispatch panel rows.
/// Uses highlight at 8% opacity — no shadows, no scale.
///
/// Note: ButtonStyle cannot accept a Model, so DesignSystem.standard
/// is read directly here. This is the accepted exception for ButtonStyles.
///
struct DispatchRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let ds = DesignSystem.standard
        configuration.label
            .background(
                configuration.isPressed
                    ? ds.colors.highlight.opacity(0.08)
                    : .clear
            )
            .animation(ds.animation.fast, value: configuration.isPressed)
    }
}
