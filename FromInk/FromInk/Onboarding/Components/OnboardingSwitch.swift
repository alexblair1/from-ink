import SwiftUI

/// Custom switch matching the design's permissions toggles.
/// 48×28pt track with a 22pt paper thumb. Ink-on when on, rule-color
/// when off. Linear 100ms animation matches the design system.
///
/// **Non-interactive**: the whole permission row is the tap target,
/// not the switch alone. The switch is a visual indicator only — taps
/// inside the row (anywhere) flip the state. This is hidden from
/// VoiceOver; the row exposes the toggle state via `accessibilityValue`.
///
struct OnboardingSwitch: View {
    let model: Model

    var body: some View {
        ZStack(alignment: model.isOn ? .trailing : .leading) {
            Capsule()
                .fill(model.isOn ? model.activeTrack : model.inactiveTrack)
                .frame(width: model.trackWidth, height: model.trackHeight)
            Circle()
                .fill(model.thumbColor)
                .frame(width: model.thumbDiameter, height: model.thumbDiameter)
                .padding(.horizontal, model.thumbPadding)
        }
        .animation(model.animation, value: model.isOn)
        .accessibilityHidden(true)
    }
}

extension OnboardingSwitch {
    struct Model {
        let isOn: Bool
        let trackWidth: CGFloat
        let trackHeight: CGFloat
        let thumbDiameter: CGFloat
        let thumbPadding: CGFloat
        let activeTrack: Color
        let inactiveTrack: Color
        let thumbColor: Color
        let animation: Animation
    }
}

extension OnboardingSwitch.Model {
    init(isOn: Bool, ds: DesignSystem = .standard) {
        self.isOn = isOn
        self.trackWidth = ds.layout.onboardingSwitchTrackWidth
        self.trackHeight = ds.layout.onboardingSwitchTrackHeight
        self.thumbDiameter = ds.layout.onboardingSwitchThumbDiameter
        self.thumbPadding = ds.layout.onboardingSwitchThumbInset
        self.activeTrack = ds.colors.ink
        self.inactiveTrack = ds.colors.rule
        self.thumbColor = ds.colors.paper
        self.animation = ds.animation.standard
    }
}
