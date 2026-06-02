import SwiftUI

/// A single row in the settings home — serif title on the left, an
/// optional right-aligned `StatusHint` ("Daylight", "Right", etc.),
/// and a trailing chevron. No icon, per the design's icon-free row
/// treatment.
///
/// Status hint is the design's "do I need to look in here?" answer —
/// quiet prose-grey when present, omitted entirely when there's
/// nothing meaningful to say.
///
/// Component view: zero state, zero TCA.
///
struct SettingsRow: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: ds.spacing.sm) {
                Text(model.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)

                Spacer()

                if let hint = model.statusHint {
                    statusHintLabel(hint)
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ds.colors.ink3)
            }
            .padding(.horizontal, ds.spacing.base)
            .frame(height: ds.layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Renders the right-side status hint with the case-appropriate
    /// typography + color. Neutral hints stay in serif prose; attention
    /// hints flip to mono uppercase + `flagRed` for at-a-glance read.
    /// The mono attention treatment is rendered via the shared
    /// `MonoLabel` primitive so the integration row's "Re-authenticate"
    /// label and the pending-row status pill stay typographically in
    /// sync with this one.
    @ViewBuilder
    private func statusHintLabel(_ hint: StatusHint) -> some View {
        switch hint {
        case .neutral(let text):
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(ds.colors.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
        case .attention(let text):
            MonoLabel(text, size: 10, color: ds.colors.flagRed)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Model

extension SettingsRow {
    struct Model: Identifiable {
        let id: SettingsDestination
        let title: String
        let statusHint: StatusHint?
        let onTap: () -> Void
    }
}
