import SwiftUI

/// Empty state shown when there are no folders or notebooks yet.
/// Editorial tone — invites the user to create their first notebook.
///
struct HomeEmptyState: View {
    let onCreateNotebook: () -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: ds.spacing.base) {
            Spacer().frame(height: ds.spacing.xxl)

            Image(systemName: "book.closed")
                .font(.system(size: 36, weight: .ultraLight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ds.colors.ink3)

            VStack(spacing: 6) {
                Text(AppStrings.Home.startWriting)
                    .font(ds.typography.display(size: 22))
                    .foregroundStyle(ds.colors.ink)

                Text(AppStrings.Home.emptySubtitle)
                    .font(ds.typography.subheadline)
                    .foregroundStyle(ds.colors.ink2)
            }

            InkButton(AppStrings.Home.newNotebook, style: .filled, icon: "plus", action: onCreateNotebook)
                .padding(.top, ds.spacing.xs)

            Spacer().frame(height: ds.spacing.xxl)
        }
        .frame(maxWidth: .infinity)
    }
}
