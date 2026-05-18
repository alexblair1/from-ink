import SwiftUI

/// The small mono-styled affordance rendered after the masthead date.
///
/// Carries two pieces of state-derived information:
/// 1. **Chevron rotation** — rotated 180° when the wheel is open, signalling
///    the disclosure-style relationship between the masthead and the wheel.
/// 2. **Label text** — `"SCRUB DATES"` when the wheel is open or the user is
///    viewing today; a locale-formatted relative date (e.g. `"3 DAYS AGO"`,
///    `"IN 1 WEEK"`) when the user is warped to a non-today day.
///
/// Stateless component — both pieces are pre-resolved in the `Model` init.
///
struct MastheadPill: View {
    let model: Model

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: model.chevronSize, weight: .medium))
                .rotationEffect(model.chevronRotation)
            Text(model.text)
                .font(.system(size: model.fontSize, weight: .medium, design: .monospaced))
                .tracking(model.tracking)
                .textCase(.uppercase)
        }
        .foregroundStyle(model.foreground)
    }
}

// MARK: - Model

extension MastheadPill {
    struct Model: Equatable {
        let text: String
        let chevronRotation: Angle
        let chevronSize: CGFloat
        let fontSize: CGFloat
        let tracking: CGFloat
        let foreground: Color
    }
}

// MARK: - Model init

extension MastheadPill.Model {
    init(
        text: String,
        isExpanded: Bool,
        ds: DesignSystem = .standard
    ) {
        self.text = text
        self.chevronRotation = isExpanded ? .degrees(180) : .zero
        self.chevronSize = 10
        self.fontSize = 10
        self.tracking = 1.4
        // Quieter when wheel closed; full-ink when open — matches the
        // React "color: wheelOpen ? t.ink : t.ink2" rule.
        self.foreground = isExpanded ? ds.colors.ink : ds.colors.ink2
    }
}
