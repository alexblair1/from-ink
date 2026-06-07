import SwiftUI

/// Small X dismiss button rendered in the top-right corner of the
/// container on the subscription screen. Replaces a textual "Maybe
/// later" link — at large Dynamic Type sizes a mono-uppercase footer
/// link grows into a giant dead zone, whereas a corner X stays compact
/// and out of the primary CTA's visual hierarchy.
///
/// 44pt hit target (matches `ds.layout.hitTarget`) — the icon glyph is
/// smaller but the tap region fills the full target.
///
struct OnboardingCloseButton: View {
    let model: Model

    var body: some View {
        Button(action: model.action) {
            Image(systemName: model.icon)
                .font(model.iconFont)
                .foregroundStyle(model.iconColor)
                .symbolRenderingMode(.monochrome)
                .frame(width: model.hitTarget, height: model.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

extension OnboardingCloseButton {
    struct Model {
        let icon: String
        let iconFont: Font
        let iconColor: Color
        let hitTarget: CGFloat
        let accessibilityLabel: String
        let action: () -> Void
    }
}

extension OnboardingCloseButton.Model {
    init(action: @escaping () -> Void, ds: DesignSystem = .standard) {
        self.icon = "xmark"
        self.iconFont = .system(.body, weight: .regular)
        self.iconColor = ds.colors.ink2
        self.hitTarget = ds.layout.hitTarget
        self.accessibilityLabel = AppStrings.Onboarding.closeButton
        self.action = action
    }
}
