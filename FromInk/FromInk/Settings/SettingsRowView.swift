import SwiftUI

/// The canonical Settings content row. One component, used by every
/// row in the Settings sheet that has the shape:
/// `[title] (optional [secondaryText | statusBadge]) (optional [chevron])`.
///
/// Replaces the prior `SettingsRow`, `IntegrationAccountRow`, and
/// `IntegrationPendingRow` (which each rolled their own near-identical
/// layouts and drifted typographically). Cohesion lives here: row
/// title size, weight, color, padding, hit target, and accessory
/// treatment are pinned to a single source.
///
/// Mono affordances ("+ ADD ACCOUNT", future "+ NEW THEME") use the
/// sibling `SettingsActionRow` — its shape is different enough
/// (full-width mono label, no chevron, no trailing) that forcing it
/// through this Model would muddy both.
///
/// For multi-line rows with leading icons (Permissions), use the
/// dedicated component in `PermissionsDetailView`.
///
/// Component view: zero state, zero TCA, zero DesignSystem access.
/// Every visual value is pre-resolved on the Model in its init.
///
struct SettingsRowView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: model.contentSpacing) {
                Text(model.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                trailing

                if let chevron = model.chevron {
                    Image(systemName: "chevron.forward")
                        .font(chevron.font)
                        .foregroundStyle(chevron.color)
                }
            }
            .padding(.horizontal, model.horizontalPadding)
            .frame(minHeight: model.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Trailing content. `statusBadge` and `secondaryText` are mutually
    /// exclusive — if a row has a real status to communicate (token
    /// expired, in-flight OAuth, attention required), it uses the
    /// mono badge. Otherwise the prose secondary text appears (current
    /// preference value, email address, etc.).
    @ViewBuilder
    private var trailing: some View {
        if let badge = model.statusBadge {
            MonoLabel(badge.text, size: badge.size, color: badge.color)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let secondary = model.secondaryText {
            Text(secondary)
                .font(model.secondaryFont)
                .foregroundStyle(model.secondaryColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Model

extension SettingsRowView {
    struct Model: Identifiable {
        /// Stable per-row identity for SwiftUI's ForEach. Adapter
        /// builds these from destinations, account IDs, etc.
        let id: String
        let title: String
        let titleFont: Font
        let titleColor: Color
        /// Prose secondary text — mutually exclusive with `statusBadge`.
        let secondaryText: String?
        let secondaryFont: Font
        let secondaryColor: Color
        /// Mono status pill — overrides `secondaryText` when present.
        let statusBadge: StatusBadge?
        /// Trailing chevron config, or `nil` to suppress.
        let chevron: Chevron?
        let contentSpacing: CGFloat
        let horizontalPadding: CGFloat
        let minHeight: CGFloat
        let onTap: () -> Void
    }

    /// Chevron visual config — pre-resolved so the view doesn't pick
    /// font weight or color itself.
    struct Chevron: Equatable {
        let font: Font
        let color: Color
    }

    /// A mono status pill at the trailing edge of the row. Color
    /// encodes intent (ink = live/active, ink2 = neutral history,
    /// flagRed = attention required) and the text is the literal
    /// label rendered uppercase via `MonoLabel`.
    struct StatusBadge: Equatable {
        let text: String
        let color: Color
        let size: CGFloat
    }
}

// MARK: - Model init (resolves visuals from DesignSystem)

extension SettingsRowView.Model {
    /// Convenience init — callers pass semantic inputs (title text,
    /// `titleIsBold`, secondary text / badge, whether to show the
    /// chevron) and this init resolves every visual value off
    /// `DesignSystem`. The view sees only the resolved fields.
    init(
        id: String,
        title: String,
        titleIsBold: Bool = false,
        secondaryText: String? = nil,
        statusBadge: SettingsRowView.StatusBadge? = nil,
        showsChevron: Bool = true,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.title = title
        self.titleFont = .system(
            size: 17,
            weight: titleIsBold ? .medium : .regular,
            design: .serif
        )
        self.titleColor = ds.colors.ink
        self.secondaryText = secondaryText
        self.secondaryFont = .system(size: 13, weight: .regular, design: .serif)
        self.secondaryColor = ds.colors.ink2
        self.statusBadge = statusBadge
        self.chevron = showsChevron
            ? SettingsRowView.Chevron(
                font: .system(size: 12, weight: .medium),
                color: ds.colors.ink3
            )
            : nil
        self.contentSpacing = ds.spacing.sm
        self.horizontalPadding = ds.spacing.lg
        self.minHeight = ds.layout.hitTarget
        self.onTap = onTap
    }
}
