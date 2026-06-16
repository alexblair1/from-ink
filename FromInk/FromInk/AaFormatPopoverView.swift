import SwiftUI

/// The "Aa" formatting popover for the iPhone / iPad-compact keyboard
/// accessory bar (EDD §14.4.2). Component view — no TCA imports, reads
/// a flat Model resolved by the wiring view.
///
/// **Layout.** Three stacked sections separated by 1pt rules, inside
/// the same floating-chrome capsule the slash menu uses (paper
/// background, 1pt border, shadow tokens, capsule corner radius):
///
///   1. Block type — one tappable row per type (Title / Heading /
///      Subheading / Body / Code / Block Quote), a checkmark on the
///      active type.
///   2. Inline toggles — B / I / U / S as a row of square toggles,
///      filled when active.
///   3. List style — Bulleted / Numbered / Checklist rows.
///
/// **Interaction.** Each row / toggle fires its `onTap`; the wiring
/// view maps it to an `EditorCommand`. Tap commits; the wiring view
/// dismisses the popover. Unavailable options (checklist) render at
/// reduced opacity with a "Soon" badge and are disabled, so enabling
/// them later is a wiring change, not a view change.
struct AaFormatPopoverView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section(model.blockRows)
            rule
            inlineToggleRow
            rule
            section(model.listRows)
        }
        .padding(.vertical, model.contentVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
                .fill(model.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
                .strokeBorder(model.ruleColor, lineWidth: model.borderWidth)
        )
        .shadow(
            color: model.shadowPrimary.color,
            radius: model.shadowPrimary.radius,
            x: model.shadowPrimary.x,
            y: model.shadowPrimary.y
        )
        .shadow(
            color: model.shadowAmbient.color,
            radius: model.shadowAmbient.radius,
            x: model.shadowAmbient.x,
            y: model.shadowAmbient.y
        )
        .frame(width: model.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
    }

    // MARK: - Sections

    private func section(_ rows: [Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                rowButton(row)
            }
        }
    }

    private func rowButton(_ row: Row) -> some View {
        Button(action: row.onTap) {
            HStack(spacing: model.rowContentGap) {
                Image(systemName: row.icon)
                    .font(.system(size: model.iconSize))
                    .frame(width: model.iconColumnWidth)
                Text(row.title)
                    .font(model.rowFont)
                Spacer(minLength: model.rowTrailingMinGap)
                if row.isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: model.iconSize, weight: .semibold))
                }
                if row.isComingSoon {
                    Text(model.comingSoonBadge)
                        .font(model.badgeFont)
                        .tracking(model.badgeTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(model.ink3)
                }
            }
            .foregroundStyle(row.isComingSoon ? model.ink3 : model.ink)
            .padding(.horizontal, model.contentHorizontalPadding)
            .frame(minHeight: model.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.isComingSoon)
        .opacity(row.isComingSoon ? model.comingSoonOpacity : 1)
        .accessibilityAddTraits(row.isActive ? [.isSelected] : [])
    }

    private var inlineToggleRow: some View {
        HStack(spacing: model.inlineToggleGap) {
            ForEach(model.inlineToggles) { toggle in
                Button(action: toggle.onTap) {
                    Image(systemName: toggle.icon)
                        .font(.system(size: model.inlineIconSize, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: model.rowMinHeight)
                        .background(
                            RoundedRectangle(cornerRadius: model.inlineToggleCornerRadius, style: .continuous)
                                .fill(toggle.isActive ? model.ink : Color.clear)
                        )
                        .foregroundStyle(toggle.isActive ? model.paperOnInk : model.ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(toggle.accessibilityLabel)
                .accessibilityAddTraits(toggle.isActive ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, model.contentHorizontalPadding)
        .padding(.vertical, model.spacingBetweenSections)
    }

    private var rule: some View {
        Rectangle()
            .fill(model.ruleColor)
            .frame(height: 1)
    }
}

// MARK: - Model

extension AaFormatPopoverView {
    /// A block-type or list-style row. `isActive` shows the checkmark
    /// (the current block kind); `isComingSoon` dims + disables.
    struct Row: Identifiable, Equatable {
        let id: String
        let icon: String
        let title: String
        let isActive: Bool
        let isComingSoon: Bool
        let onTap: () -> Void

        init(
            id: String,
            icon: String,
            title: String,
            isActive: Bool = false,
            isComingSoon: Bool = false,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.icon = icon
            self.title = title
            self.isActive = isActive
            self.isComingSoon = isComingSoon
            self.onTap = onTap
        }

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.id == rhs.id && lhs.icon == rhs.icon && lhs.title == rhs.title
                && lhs.isActive == rhs.isActive && lhs.isComingSoon == rhs.isComingSoon
        }
    }

    /// One inline-format toggle (bold / italic / underline / strike).
    struct InlineToggle: Identifiable, Equatable {
        let id: String
        let icon: String
        let accessibilityLabel: String
        let isActive: Bool
        let onTap: () -> Void

        static func == (lhs: InlineToggle, rhs: InlineToggle) -> Bool {
            lhs.id == rhs.id && lhs.icon == rhs.icon
                && lhs.accessibilityLabel == rhs.accessibilityLabel && lhs.isActive == rhs.isActive
        }
    }

    struct Model {
        let blockRows: [Row]
        let inlineToggles: [InlineToggle]
        let listRows: [Row]
        let comingSoonBadge: String
        let accessibilityLabel: String

        let width: CGFloat
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let contentHorizontalPadding: CGFloat
        let contentVerticalPadding: CGFloat
        let rowVerticalPadding: CGFloat
        let rowContentGap: CGFloat
        let rowTrailingMinGap: CGFloat
        let iconColumnWidth: CGFloat
        let iconSize: CGFloat
        let comingSoonOpacity: CGFloat

        let inlineToggleGap: CGFloat
        let inlineIconSize: CGFloat
        let inlineToggleCornerRadius: CGFloat
        /// Min row height — applies to block rows AND inline-toggle
        /// chips. 44pt per Apple HIG so every row is a real tap target.
        let rowMinHeight: CGFloat
        /// Padding above the inline-toggle row separating it from the
        /// rules above and below.
        let spacingBetweenSections: CGFloat

        let paper: Color
        let ink: Color
        let ink3: Color
        let paperOnInk: Color
        let ruleColor: Color

        let rowFont: Font
        let badgeFont: Font
        let badgeTracking: CGFloat

        let shadowPrimary: ShadowTokens.Shadow
        let shadowAmbient: ShadowTokens.Shadow
    }
}

extension AaFormatPopoverView.Model {
    init(
        blockRows: [AaFormatPopoverView.Row],
        inlineToggles: [AaFormatPopoverView.InlineToggle],
        listRows: [AaFormatPopoverView.Row],
        ds: DesignSystem = .standard
    ) {
        self.blockRows = blockRows
        self.inlineToggles = inlineToggles
        self.listRows = listRows
        self.comingSoonBadge = AppStrings.AccessoryBar.comingSoonBadge
        self.accessibilityLabel = AppStrings.AccessoryBar.aaPopoverAccessibilityLabel

        self.width = 260
        self.cornerRadius = ds.layout.toolbarCapsuleCornerRadius
        self.borderWidth = ds.layout.borderWidth
        self.contentHorizontalPadding = ds.spacing.md
        self.contentVerticalPadding = ds.spacing.xs
        self.rowVerticalPadding = ds.spacing.sm
        self.rowContentGap = ds.spacing.md
        self.rowTrailingMinGap = ds.spacing.sm
        self.iconColumnWidth = 22
        self.iconSize = 14
        self.comingSoonOpacity = 0.5

        self.inlineToggleGap = ds.spacing.xs
        self.inlineIconSize = 15
        self.inlineToggleCornerRadius = ds.cornerRadius.chip
        self.rowMinHeight = 44
        self.spacingBetweenSections = ds.spacing.xs

        self.paper = ds.colors.paper
        self.ink = ds.colors.ink
        self.ink3 = ds.colors.ink3
        self.paperOnInk = ds.colors.paperOnInk
        self.ruleColor = ds.colors.rule

        self.rowFont = .system(.subheadline, design: .default)
        self.badgeFont = .system(size: 9.5, weight: .medium, design: .monospaced)
        self.badgeTracking = 1.3

        self.shadowPrimary = ds.shadow.toolbarCapsulePrimary
        self.shadowAmbient = ds.shadow.toolbarCapsuleAmbient
    }
}
