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
/// Component view: zero state, zero TCA.
///
struct SettingsRowView: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: ds.spacing.sm) {
                Text(model.title)
                    .font(.system(
                        size: 17,
                        weight: model.titleIsBold ? .medium : .regular,
                        design: .serif
                    ))
                    .foregroundStyle(model.titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                trailing

                if model.showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ds.colors.ink3)
                }
            }
            .padding(.horizontal, ds.spacing.lg)
            .frame(minHeight: ds.layout.hitTarget)
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
            MonoLabel(badge.text, size: 10, color: badge.color)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let secondary = model.secondaryText {
            Text(secondary)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(ds.colors.ink2)
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
        /// Bold variant — used by IntegrationAccountRow's "this is
        /// the default" treatment. Defaults to false; the adapter
        /// flips it only when meaningful.
        let titleIsBold: Bool
        /// Title color — defaults to `ink`. The pending row uses
        /// `ink2` to signal "this row is in flight, not yet
        /// committed content."
        let titleColor: Color
        /// Prose secondary text — 13pt serif ink2. Mutually exclusive
        /// with `statusBadge`.
        let secondaryText: String?
        /// Mono status pill — overrides `secondaryText` when present.
        let statusBadge: StatusBadge?
        /// Whether to render a trailing chevron. Account rows that
        /// open detail navigation use it; in-flight pending rows
        /// don't.
        let showsChevron: Bool
        let onTap: () -> Void

        init(
            id: String,
            title: String,
            titleIsBold: Bool = false,
            titleColor: Color = ColorTokens.standard.ink,
            secondaryText: String? = nil,
            statusBadge: StatusBadge? = nil,
            showsChevron: Bool = true,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.titleIsBold = titleIsBold
            self.titleColor = titleColor
            self.secondaryText = secondaryText
            self.statusBadge = statusBadge
            self.showsChevron = showsChevron
            self.onTap = onTap
        }
    }

    /// A mono status pill at the trailing edge of the row. Color
    /// encodes intent (ink = live/active, ink2 = neutral history,
    /// flagRed = attention required) and the text is the literal
    /// label rendered uppercase via `MonoLabel`.
    struct StatusBadge: Equatable {
        let text: String
        let color: Color
    }
}
