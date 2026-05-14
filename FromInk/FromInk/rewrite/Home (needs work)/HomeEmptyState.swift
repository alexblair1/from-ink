import SwiftUI

/// Empty state shown when there are no folders or notebooks yet.
/// Editorial tone — invites the user to create their first notebook.
///
struct HomeEmptyState: View {
    let model: Model

    var body: some View {
        VStack(spacing: model.sectionSpacing) {
            Spacer().frame(height: model.topSpacing)

            Image(systemName: model.icon)
                .font(.system(size: model.iconSize, weight: .ultraLight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.iconColor)

            VStack(spacing: model.textSpacing) {
                Text(model.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)

                Text(model.subtitle)
                    .font(model.subtitleFont)
                    .foregroundStyle(model.subtitleColor)
            }

            InkButton(model.buttonLabel, style: .filled, icon: "plus", action: model.onCreateNotebook)
                .padding(.top, model.buttonTopPadding)

            Spacer().frame(height: model.topSpacing)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Model

extension HomeEmptyState {
    struct Model {
        let icon: String
        let iconSize: CGFloat
        let iconColor: Color
        let title: String
        let titleFont: Font
        let titleColor: Color
        let subtitle: String
        let subtitleFont: Font
        let subtitleColor: Color
        let buttonLabel: String
        let onCreateNotebook: () -> Void
        let sectionSpacing: CGFloat
        let topSpacing: CGFloat
        let textSpacing: CGFloat
        let buttonTopPadding: CGFloat
    }
}

// MARK: - Model init

extension HomeEmptyState.Model {
    init(
        onCreateNotebook: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.icon = "book.closed"
        self.iconSize = ds.layout.emptyStateIconSize
        self.iconColor = ds.colors.ink3
        self.title = AppStrings.Home.startWriting
        self.titleFont = ds.typography.display(size: 22)
        self.titleColor = ds.colors.ink
        self.subtitle = AppStrings.Home.emptySubtitle
        self.subtitleFont = ds.typography.subheadline
        self.subtitleColor = ds.colors.ink2
        self.buttonLabel = AppStrings.Home.newNotebook
        self.onCreateNotebook = onCreateNotebook
        self.sectionSpacing = ds.spacing.base
        self.topSpacing = ds.spacing.xxl
        self.textSpacing = ds.spacing.xs
        self.buttonTopPadding = ds.spacing.xs
    }
}
