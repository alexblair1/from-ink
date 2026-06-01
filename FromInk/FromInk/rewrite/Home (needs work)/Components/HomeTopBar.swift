import SwiftUI

/// Sticky top bar: settings (left), wordmark (center), import-PDF + compose
/// (right). Trailing area renders the import button to the left of compose
/// so the right edge stays anchored on the canonical "new" action.
/// Component view — no TCA imports.
///
struct HomeTopBar: View {
    let model: Model

    var body: some View {
        HStack(spacing: 0) {
            Button(action: model.onSettings) {
                Image(systemName: model.leadingIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(model.title)
                .font(model.titleFont)
                .foregroundStyle(model.titleColor)
                .tracking(model.titleTracking)

            Spacer()

            Button(action: model.onImportPDF) {
                Image(systemName: model.importPDFIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.importPDFAccessibilityLabel)

            Button(action: model.onCompose) {
                Image(systemName: model.trailingIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.topPadding)
        .padding(.bottom, model.bottomPadding)
    }
}

// MARK: - Model

extension HomeTopBar {
    struct Model {
        let title: String
        let leadingIcon: String
        let importPDFIcon: String
        let importPDFAccessibilityLabel: String
        let trailingIcon: String
        let onSettings: () -> Void
        let onImportPDF: () -> Void
        let onCompose: () -> Void
        let titleFont: Font
        let titleColor: Color
        let titleTracking: CGFloat
        let iconColor: Color
        let iconSize: CGFloat
        let hitTarget: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }
}

// MARK: - Model init

extension HomeTopBar.Model {
    init(
        onSettings: @escaping () -> Void,
        onImportPDF: @escaping () -> Void,
        onCompose: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.title = AppStrings.Home.title
        self.leadingIcon = "gearshape"
        self.importPDFIcon = "doc.badge.plus"
        self.importPDFAccessibilityLabel = AppStrings.Library.importPDFButton
        self.trailingIcon = "square.and.pencil"
        self.onSettings = onSettings
        self.onImportPDF = onImportPDF
        self.onCompose = onCompose
        self.titleFont = ds.typography.wordmark
        self.titleColor = ds.colors.ink
        self.titleTracking = 0.4
        self.iconColor = ds.colors.ink
        self.iconSize = 17
        self.hitTarget = ds.layout.hitTarget
        self.horizontalPadding = ds.spacing.lg
        self.topPadding = ds.spacing.sm
        self.bottomPadding = ds.spacing.xs
    }
}
