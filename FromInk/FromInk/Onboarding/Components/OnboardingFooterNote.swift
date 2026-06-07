import SwiftUI

/// Mono uppercase note at the very bottom of the footer.
/// Used on the subscription screen ("Then $11.99/year · Cancel anytime").
///
struct OnboardingFooterNote: View {
    let model: Model

    var body: some View {
        Text(model.text)
            .font(model.font)
            .tracking(model.tracking)
            .textCase(.uppercase)
            .foregroundStyle(model.color)
            .multilineTextAlignment(.center)
    }
}

extension OnboardingFooterNote {
    struct Model: Equatable {
        let text: String
        let font: Font
        let tracking: CGFloat
        let color: Color
    }
}

extension OnboardingFooterNote.Model {
    init(text: String, ds: DesignSystem = .standard) {
        self.text = text
        self.font = ds.typography.onboardingFooterNote
        self.tracking = ds.typography.monoNoteTracking
        self.color = ds.colors.ink3
    }
}
