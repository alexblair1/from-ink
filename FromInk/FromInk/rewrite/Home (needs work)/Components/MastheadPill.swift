import SwiftUI

/// The chevron affordance rendered after the masthead date — the visual
/// indicator that the date is tappable to open the Time Warp wheel.
///
/// Originally included a "SCRUB DATES" / relative-time text label, but the
/// label took too much horizontal space on iPhone and didn't survive
/// verbose translations cleanly. The component is now just the chevron,
/// rendered larger to read as a clear button affordance on its own.
///
/// Rotates 180° when the wheel is open. Color follows full ink when open,
/// quieted (ink2) when closed.
///
struct MastheadPill: View {
    let model: Model

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: model.chevronSize, weight: .medium))
            .rotationEffect(model.chevronRotation)
            .foregroundStyle(model.foreground)
    }
}

// MARK: - Model

extension MastheadPill {
    struct Model: Equatable {
        let chevronRotation: Angle
        let chevronSize: CGFloat
        let foreground: Color
    }
}

// MARK: - Model init

extension MastheadPill.Model {
    init(
        isExpanded: Bool,
        ds: DesignSystem = .standard
    ) {
        self.chevronRotation = isExpanded ? .degrees(180) : .zero
        // Larger than the previous 10pt text-companion size so the chevron
        // reads as an affordance on its own without a text label.
        self.chevronSize = 16
        // Quieter when wheel closed; full-ink when open — matches the
        // React "color: wheelOpen ? t.ink : t.ink2" rule.
        self.foreground = isExpanded ? ds.colors.ink : ds.colors.ink2
    }
}
