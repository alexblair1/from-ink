import SwiftUI

/// Full-width primary CTA used at the bottom of every onboarding screen.
///
/// Visual contract:
/// - Ink background, paper foreground, square corners (cornerRadius 0).
/// - SF Pro 16pt medium label, with a small italic serif "→" appended
///   as a decorative arrow.
/// - Single view identity across all four steps — only the label and
///   `action` change. The container places exactly one of these and
///   never wraps it conditionally, so SwiftUI keeps it stable.
///
struct OnboardingPrimaryButton: View {
    let model: Model

    var body: some View {
        Button(action: model.action) {
            HStack(spacing: model.arrowSpacing) {
                Text(model.title)
                    .font(model.labelFont)
                Text(verbatim: "→")
                    .font(model.arrowFont)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, model.verticalPadding)
            .foregroundStyle(model.foreground)
            .background(model.background)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.title)
    }
}

extension OnboardingPrimaryButton {
    struct Model {
        let title: String
        let labelFont: Font
        let arrowFont: Font
        let arrowSpacing: CGFloat
        let verticalPadding: CGFloat
        let foreground: Color
        let background: Color
        let action: () -> Void
    }
}

extension OnboardingPrimaryButton.Model {
    init(title: String, action: @escaping () -> Void, ds: DesignSystem = .standard) {
        self.title = title
        self.labelFont = ds.typography.onboardingButtonLabel
        self.arrowFont = .system(.title3, design: .serif).weight(.light).italic()
        self.arrowSpacing = ds.spacing.sm
        self.verticalPadding = ds.spacing.base
        self.foreground = ds.colors.paperOnInk
        self.background = ds.colors.ink
        self.action = action
    }
}
