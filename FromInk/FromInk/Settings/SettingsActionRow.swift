import SwiftUI

/// A mono uppercase action affordance pinned inside a settings group
/// (e.g. "+ ADD ACCOUNT", future "+ NEW THEME"). The visual grammar
/// matches Dispatch's "SEND TO …" pattern: system action language is
/// always SF Mono uppercase, distinct from content rows which use
/// serif New York.
///
/// Replaces the prior `IntegrationAddAccountRow`. The previous
/// implementation rendered as sans-serif 13pt, which read as a
/// stray content label rather than an affordance — the user
/// couldn't tell at a glance that tapping would initiate a system
/// flow.
///
/// Component view: zero state, zero TCA.
///
struct SettingsActionRow: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: 0) {
                MonoLabel(model.label, size: 11, color: ds.colors.ink)
                Spacer()
            }
            .padding(.horizontal, ds.spacing.lg)
            .frame(minHeight: ds.layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension SettingsActionRow {
    struct Model: Equatable {
        let label: String
        let onTap: () -> Void

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.label == rhs.label
        }
    }
}
