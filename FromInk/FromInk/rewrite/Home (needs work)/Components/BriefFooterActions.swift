import SwiftUI

/// "View details →" filled button + "COLLAPSE ^" text button.
/// Component view — no TCA imports.
///
struct BriefFooterActions: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: model.innerSpacing) {
                InkButton(
                    "\(model.detailsLabel) →",
                    style: .filled,
                    action: model.onViewDetails
                )

                Button(action: model.onCollapse) {
                    HStack(spacing: model.collapseIconSpacing) {
                        Text(model.collapseLabel)
                        Image(systemName: "chevron.up")
                            .font(.system(
                                size: model.collapseIconSize,
                                weight: .medium
                            ))
                    }
                    .font(model.collapseFont)
                    .tracking(model.collapseTracking)
                    .foregroundStyle(model.collapseColor)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, model.topPadding)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.sectionTopPadding)
    }
}

// MARK: - Model

extension BriefFooterActions {
    struct Model {
        let detailsLabel: String
        let collapseLabel: String
        let onViewDetails: () -> Void
        let onCollapse: () -> Void
        let collapseFont: Font
        let collapseColor: Color
        let collapseTracking: CGFloat
        let collapseIconSize: CGFloat
        let collapseIconSpacing: CGFloat
        let innerSpacing: CGFloat
        let topPadding: CGFloat
        let sectionTopPadding: CGFloat
        let horizontalPadding: CGFloat
    }
}

// MARK: - Model init

extension BriefFooterActions.Model {
    init(
        onViewDetails: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.detailsLabel = AppStrings.Home.viewDetails
        self.collapseLabel = AppStrings.Home.collapse.uppercased()
        self.onViewDetails = onViewDetails
        self.onCollapse = onCollapse
        self.collapseFont = ds.typography.monoLabel
        self.collapseColor = ds.colors.ink2
        self.collapseTracking = 11 * 0.18
        self.collapseIconSize = 9
        self.collapseIconSpacing = ds.spacing.xs
        self.innerSpacing = ds.spacing.md
        self.topPadding = ds.spacing.md
        self.sectionTopPadding = ds.spacing.base
        self.horizontalPadding = ds.spacing.lg
    }
}
