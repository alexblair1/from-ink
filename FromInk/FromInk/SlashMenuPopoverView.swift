import SwiftUI

/// Caret-anchored slash-menu popover for the Mac + iPad-regular text
/// editor surface. Component view — no TCA imports. Reads a flat
/// Model resolved by the wiring view.
///
/// **Layout.** Capsule chrome (matching the floating-toolbar
/// aesthetic — paper background, 1pt rule border, shadow tokens
/// from the design system, 26pt corner radius). Header row with
/// "Insert" + the filter text echoed; one row per matched
/// descriptor below; "no matches" empty state when nothing matches.
///
/// **Interaction.**
///   - Tap a row → `onCommandTapped(SlashCommand)` fires.
///   - Hovering / keyboard-arrow nav highlights `selectedID`.
///   - The wiring view owns the keyboard navigation observer
///     (`UIKeyCommand` / `NSResponder`) and forwards arrow / enter
///     / escape via the parent reducer.
///
/// **Coming-soon discipline.** Unavailable commands render at
/// reduced opacity with a "Soon" badge; the wiring view's tap
/// handler still fires `onCommandTapped` so future enablement is
/// a one-line registry edit, not a view-layer change.
struct SlashMenuPopoverView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            content
        }
        .background(capsuleBackground)
        .overlay(capsuleBorder)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.headerTitle)
                .font(model.headerFont)
                .foregroundStyle(model.secondaryColor)
                .textCase(.uppercase)
                .tracking(model.headerTracking)
            if !model.filterText.isEmpty {
                Text("/\(model.filterText)")
                    .font(model.filterFont)
                    .foregroundStyle(model.ink)
                    .monospaced()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, model.contentHorizontalPadding)
        .padding(.top, model.contentVerticalPadding)
        .padding(.bottom, model.headerBottomGap)
    }

    private var divider: some View {
        Rectangle()
            .fill(model.ruleColor)
            .frame(height: 1)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty {
            emptyState
        } else {
            rowsList
        }
    }

    private var rowsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.rows) { row in
                    rowView(for: row)
                }
            }
            .padding(.vertical, model.rowsVerticalPadding)
        }
        .frame(maxHeight: model.maxListHeight)
    }

    private func rowView(for row: Row) -> some View {
        Button(action: { row.onTap() }) {
            HStack(spacing: model.rowContentGap) {
                Image(systemName: row.icon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .foregroundStyle(row.isSelected ? model.paperOnInk : model.ink2)
                    .frame(width: model.iconColumnWidth, alignment: .center)
                Text(row.title)
                    .font(model.rowFont)
                    .foregroundStyle(row.isSelected ? model.paperOnInk : model.ink)
                    .lineLimit(1)
                Spacer(minLength: model.rowTrailingMinGap)
                if row.isComingSoon {
                    Text(model.comingSoonBadge)
                        .font(model.badgeFont)
                        .foregroundStyle(row.isSelected ? model.paperOnInk : model.ink3)
                        .textCase(.uppercase)
                        .tracking(model.badgeTracking)
                }
                if let shortcut = row.shortcutHint {
                    Text(shortcut)
                        .font(model.shortcutFont)
                        .foregroundStyle(row.isSelected ? model.paperOnInk : model.ink3)
                        .monospaced()
                }
            }
            .padding(.horizontal, model.contentHorizontalPadding)
            .padding(.vertical, model.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(row.isSelected ? model.ink : .clear)
            .opacity(row.isComingSoon && !row.isSelected ? 0.6 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.title)
        .accessibilityHint(row.isComingSoon ? model.comingSoonBadge : "")
    }

    private var emptyState: some View {
        Text(model.emptyStateText)
            .font(model.rowFont)
            .foregroundStyle(model.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, model.contentHorizontalPadding)
            .padding(.vertical, model.rowVerticalPadding * 2)
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
            .fill(model.paper)
    }

    private var capsuleBorder: some View {
        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
            .stroke(model.ruleColor, lineWidth: model.borderWidth)
    }
}

// MARK: - Model

extension SlashMenuPopoverView {
    struct Row: Identifiable, Equatable {
        let id: SlashCommand
        let icon: String
        let title: String
        let shortcutHint: String?
        let isSelected: Bool
        let isComingSoon: Bool
        let onTap: () -> Void

        /// Custom `Equatable` — `onTap` is a `() -> Void` closure
        /// that isn't `Equatable`. Identity by every other field is
        /// correct for SwiftUI diffing: identical Models built from
        /// the same call site produce identical closures, so this
        /// comparison reflects what SwiftUI sees as "the same row."
        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.id == rhs.id
                && lhs.icon == rhs.icon
                && lhs.title == rhs.title
                && lhs.shortcutHint == rhs.shortcutHint
                && lhs.isSelected == rhs.isSelected
                && lhs.isComingSoon == rhs.isComingSoon
        }
    }

    struct Model {
        let rows: [Row]
        let headerTitle: String
        let filterText: String
        let comingSoonBadge: String
        let emptyStateText: String
        let accessibilityLabel: String

        let width: CGFloat
        let maxListHeight: CGFloat
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let contentHorizontalPadding: CGFloat
        let contentVerticalPadding: CGFloat
        let headerBottomGap: CGFloat
        let rowsVerticalPadding: CGFloat
        let rowVerticalPadding: CGFloat
        let iconColumnWidth: CGFloat
        let iconSize: CGFloat
        let rowContentGap: CGFloat
        let rowTrailingMinGap: CGFloat

        let paper: Color
        let ink: Color
        let ink2: Color
        let ink3: Color
        let paperOnInk: Color
        let ruleColor: Color
        let secondaryColor: Color

        let headerFont: Font
        let filterFont: Font
        let rowFont: Font
        let shortcutFont: Font
        let badgeFont: Font

        let headerTracking: CGFloat
        let badgeTracking: CGFloat

        let shadowPrimary: ShadowTokens.Shadow
        let shadowAmbient: ShadowTokens.Shadow
    }
}

// MARK: - Model init (adapter convenience)

extension SlashMenuPopoverView.Model {
    init(
        rows: [SlashMenuPopoverView.Row],
        filterText: String,
        ds: DesignSystem = .standard
    ) {
        self.rows = rows
        self.filterText = filterText
        self.headerTitle = AppStrings.SlashMenu.header
        self.comingSoonBadge = AppStrings.SlashMenu.comingSoonBadge
        self.emptyStateText = AppStrings.SlashMenu.noMatches
        self.accessibilityLabel = AppStrings.SlashMenu.paletteAccessibilityLabel

        self.width = 280
        self.maxListHeight = 360
        self.cornerRadius = ds.layout.toolbarCapsuleCornerRadius
        self.borderWidth = ds.layout.borderWidth
        self.contentHorizontalPadding = ds.spacing.md
        self.contentVerticalPadding = ds.spacing.sm
        self.headerBottomGap = ds.spacing.xs
        self.rowsVerticalPadding = ds.spacing.xxs
        self.rowVerticalPadding = ds.spacing.sm
        self.iconColumnWidth = 22
        self.iconSize = 14
        self.rowContentGap = ds.spacing.md
        self.rowTrailingMinGap = ds.spacing.sm

        self.paper = ds.colors.paper
        self.ink = ds.colors.ink
        self.ink2 = ds.colors.ink2
        self.ink3 = ds.colors.ink3
        self.paperOnInk = ds.colors.paperOnInk
        self.ruleColor = ds.colors.rule
        self.secondaryColor = ds.colors.ink2

        self.headerFont = .system(size: 10.5, weight: .medium, design: .monospaced)
        self.filterFont = .system(size: 11, weight: .regular, design: .monospaced)
        self.rowFont = .system(.subheadline, design: .default)
        self.shortcutFont = .system(size: 11, weight: .regular, design: .monospaced)
        self.badgeFont = .system(size: 9.5, weight: .medium, design: .monospaced)

        self.headerTracking = 2.3
        self.badgeTracking = 1.3

        self.shadowPrimary = ds.shadow.toolbarCapsulePrimary
        self.shadowAmbient = ds.shadow.toolbarCapsuleAmbient
    }
}
