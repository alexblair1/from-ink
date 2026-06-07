import SwiftUI

/// Mono uppercase text link that sits in the footer below the primary
/// button. Used for "Not now" on permissions and "Maybe later" on
/// subscription. Absent from welcome and value.
///
struct OnboardingSecondaryLink: View {
    let model: Model

    var body: some View {
        Button(action: model.action) {
            Text(model.text)
                .font(model.font)
                .tracking(model.tracking)
                .textCase(.uppercase)
                .foregroundStyle(model.color)
        }
        .buttonStyle(.plain)
    }
}

extension OnboardingSecondaryLink {
    struct Model {
        let text: String
        let font: Font
        let tracking: CGFloat
        let color: Color
        let action: () -> Void
    }
}

extension OnboardingSecondaryLink.Model {
    init(text: String, action: @escaping () -> Void, ds: DesignSystem = .standard) {
        self.text = text
        self.font = ds.typography.onboardingTextLink
        self.tracking = ds.typography.monoLinkTracking
        self.color = ds.colors.ink2
        self.action = action
    }
}
