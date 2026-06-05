import SwiftUI

/// Unified bounding-box indicator for a `NoteRegion` on a `NotePage`.
/// Replaces the separate `HeaderIndicator` + `LinkIndicator` views,
/// surfacing one rectangle that can carry multiple badges (header,
/// link, future event / reminder / PDF) along its perimeter.
///
/// Component view: zero TCA imports. Adapter resolves a
/// `NoteRegionSnapshot` into the flat `Model` so the view never
/// switches on snapshot enums.
///
/// Interactivity is deliberately limited in this revision — the
/// indicator renders the bounding box + a non-interactive badge row.
/// A follow-up adds the ellipsis chip + tap-to-edit + manage menu.
///
struct RegionIndicator: View {
    let model: Model

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Bounding rect — unified style across all region kinds.
            // Light tint fill + solid stroke, sharp corners per the
            // design-system rule (no `cornerRadius` on content).
            Rectangle()
                .fill(model.fillColor)
                .overlay(
                    Rectangle()
                        .strokeBorder(model.strokeColor, lineWidth: model.strokeWidth)
                )
                .frame(width: model.size.width, height: model.size.height)

            if !model.badges.isEmpty {
                badgeRow
                    // The badge row hangs off the top-right corner
                    // (overhanging by half the badge height) so it
                    // reads as attached to the rect rather than
                    // floating inside it.
                    .offset(x: model.badgeRowOffset.x, y: model.badgeRowOffset.y)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Badge row

    private var badgeRow: some View {
        HStack(spacing: model.badgeSpacing) {
            ForEach(model.badges) { badge in
                badgeView(badge)
            }
        }
    }

    private func badgeView(_ badge: Model.Badge) -> some View {
        Image(systemName: badge.iconSystemName)
            .font(.system(size: model.badgeIconSize, weight: .medium))
            .foregroundStyle(badge.iconColor)
            .frame(width: model.badgeFrame, height: model.badgeFrame)
            .background(badge.background)
            .accessibilityLabel(badge.accessibilityLabel)
    }
}

// MARK: - Model

extension RegionIndicator {
    struct Model: Equatable {
        let id: UUID
        let size: CGSize
        let badges: [Badge]

        // Visual style (resolved from DesignSystem at adapter time)
        let fillColor: Color
        let strokeColor: Color
        let strokeWidth: CGFloat

        // Badge row layout
        let badgeRowOffset: CGPoint
        let badgeSpacing: CGFloat
        let badgeFrame: CGFloat
        let badgeIconSize: CGFloat

        struct Badge: Equatable, Identifiable {
            /// Stable id for `ForEach` — uses the badge kind so the
            /// same kind keeps its position across renders.
            let id: Kind
            let iconSystemName: String
            let iconColor: Color
            let background: Color
            let accessibilityLabel: String

            enum Kind: String, Hashable {
                case header
                case link
                case event
                case reminder
                case pdf
            }
        }

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.id == rhs.id
                && lhs.size == rhs.size
                && lhs.badges == rhs.badges
        }
    }
}

// MARK: - Model init from a snapshot

extension RegionIndicator.Model {
    /// Adapter — builds the Model from a `NoteRegionSnapshot`.
    /// Enforces the "at-most-one badge per kind" invariant by
    /// iterating the snapshot's optional fields and emitting at most
    /// one badge per kind. The view layer never sees the rule.
    ///
    /// Future kinds (event / reminder / PDF) are NOT resolved here —
    /// they require joining against `CalendarItemLink` etc., which
    /// happens at the canvas-level adapter once the join data is
    /// available. The Model API supports them via `extraBadges`; in
    /// this revision the canvas passes `[]`.
    init(
        snapshot: NoteRegionSnapshot,
        extraBadges: [RegionIndicator.Model.Badge] = [],
        ds: DesignSystem = .standard
    ) {
        self.id = snapshot.id
        self.size = snapshot.rect.size

        var badges: [Badge] = []
        if snapshot.headerOCRText != nil {
            badges.append(.header(ds: ds))
        }
        switch snapshot.linkDestination {
        case .none:
            break
        case .external:
            badges.append(.link(ds: ds))
        case .page, .notebook:
            badges.append(.crossReference(ds: ds))
        case .pdf:
            badges.append(.pdf(ds: ds))
        case .broken:
            badges.append(.broken(ds: ds))
        }
        badges.append(contentsOf: extraBadges)
        self.badges = badges

        self.fillColor = ds.colors.ink.opacity(0.06)
        self.strokeColor = ds.colors.ink.opacity(0.20)
        self.strokeWidth = ds.layout.borderWidth

        // Badge row hangs off the top-right corner. The X offset of
        // half the badge frame and Y offset of negative half-frame
        // make the row read as a "tab" attached to the rect.
        let frame: CGFloat = 22
        self.badgeFrame = frame
        self.badgeRowOffset = CGPoint(x: frame / 2, y: -frame / 2)
        self.badgeSpacing = ds.spacing.xs
        self.badgeIconSize = 11
    }
}

// MARK: - Badge factories (kind-specific style resolution)

extension RegionIndicator.Model.Badge {
    static func header(ds: DesignSystem) -> Self {
        Self(
            id: .header,
            iconSystemName: "bookmark.fill",
            iconColor: ds.colors.paperOnInk,
            background: ds.colors.ink2,
            accessibilityLabel: AppStrings.RegionIndicator.headerBadgeAccessibility
        )
    }

    static func link(ds: DesignSystem) -> Self {
        Self(
            id: .link,
            iconSystemName: "link",
            iconColor: ds.colors.paperOnInk,
            background: ds.colors.ink2,
            accessibilityLabel: AppStrings.RegionIndicator.linkBadgeAccessibility
        )
    }

    static func crossReference(ds: DesignSystem) -> Self {
        Self(
            id: .link,
            iconSystemName: "arrow.uturn.right.circle",
            iconColor: ds.colors.paperOnInk,
            background: ds.colors.ink2,
            accessibilityLabel: AppStrings.RegionIndicator.crossRefBadgeAccessibility
        )
    }

    static func pdf(ds: DesignSystem) -> Self {
        Self(
            id: .link,
            iconSystemName: "doc.richtext",
            iconColor: ds.colors.paperOnInk,
            background: ds.colors.ink2,
            accessibilityLabel: AppStrings.RegionIndicator.pdfBadgeAccessibility
        )
    }

    static func broken(ds: DesignSystem) -> Self {
        Self(
            id: .link,
            iconSystemName: "link.badge.plus",
            iconColor: ds.colors.paperOnInk,
            // Use a slightly different background so the broken state
            // reads as off-nominal at a glance without saturating with
            // a brand-violating red.
            background: ds.colors.ink3,
            accessibilityLabel: AppStrings.RegionIndicator.brokenLinkBadgeAccessibility
        )
    }
}
