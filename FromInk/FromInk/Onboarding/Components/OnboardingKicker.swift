import SwiftUI

/// Small mono uppercase eyebrow that sits above each onboarding screen's
/// headline ("WELCOME TO", "THE IDEA", "PERMISSIONS", "FROM INK PLUS").
///
struct OnboardingKicker: View {
    let model: Model

    var body: some View {
        Text(model.text)
            .font(model.font)
            .tracking(model.tracking)
            .textCase(.uppercase)
            .foregroundStyle(model.color)
            .accessibilityAddTraits(.isHeader)
    }
}

extension OnboardingKicker {
    struct Model: Equatable {
        let text: String
        let font: Font
        let tracking: CGFloat
        let color: Color
    }
}

extension OnboardingKicker.Model {
    init(text: String, ds: DesignSystem = .standard) {
        self.text = text
        self.font = ds.typography.onboardingKicker
        self.tracking = ds.typography.kickerTracking
        self.color = ds.colors.ink2
    }
}
