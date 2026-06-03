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
/// Component view: zero state, zero TCA, zero DesignSystem access.
/// Every visual value is pre-resolved on the Model in its init.
///
struct SettingsActionRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: 0) {
                MonoLabel(model.label, size: model.labelSize, color: model.labelColor)
                Spacer()
            }
            .padding(.horizontal, model.horizontalPadding)
            .frame(minHeight: model.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension SettingsActionRow {
    struct Model: Equatable {
        let label: String
        let labelSize: CGFloat
        let labelColor: Color
        let horizontalPadding: CGFloat
        let minHeight: CGFloat
        let onTap: () -> Void

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.label == rhs.label
                && lhs.labelSize == rhs.labelSize
                && lhs.labelColor == rhs.labelColor
                && lhs.horizontalPadding == rhs.horizontalPadding
                && lhs.minHeight == rhs.minHeight
        }
    }
}

// MARK: - Model init (resolves visuals from DesignSystem)

extension SettingsActionRow.Model {
    init(
        label: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        self.labelSize = 11
        self.labelColor = ds.colors.ink
        self.horizontalPadding = ds.spacing.lg
        self.minHeight = ds.layout.hitTarget
        self.onTap = onTap
    }
}
