import SwiftUI

/// The home screen — composes sticky header, daily brief, and notebook shelf.
/// Feature view — no TCA imports.
///
struct HomeScreenView: View {
    let model: Model
    @Binding var searchText: String
    @Binding var isBriefExpanded: Bool

    private let ds = DesignSystem.standard
    @State private var stickyHeaderHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ds.colors.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: stickyHeaderHeight)

                    HomeDailyBrief(
                        model: model.dailyBrief,
                        isExpanded: $isBriefExpanded
                    )

                    if !model.notebooks.isEmpty {
                        HomeNotebookShelf(model: model.shelf)
                    }

                    if model.notebooks.isEmpty {
                        homeEmptyState
                    }

                    Spacer().frame(height: ds.spacing.xxl)
                }
            }

            // Sticky header
            VStack(spacing: 0) {
                HomeTopBar(model: model.topBar)

                HomeSearchField(
                    model: .init(),
                    text: $searchText
                )
            }
            .background(ds.colors.paper)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                stickyHeaderHeight = height
            }
        }
    }

    private var homeEmptyState: some View {
        VStack(spacing: ds.spacing.md) {
            Spacer().frame(height: ds.spacing.xxl)
            Text(AppStrings.Home.startWriting)
                .font(ds.typography.editorBody)
                .foregroundStyle(ds.colors.ink)
            Text(AppStrings.Home.emptySubtitle)
                .font(ds.typography.subheadline)
                .foregroundStyle(ds.colors.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ds.spacing.lg)
    }
}

// MARK: - Model

extension HomeScreenView {
    struct Model {
        let topBar: HomeTopBar.Model
        let dailyBrief: HomeDailyBrief.Model
        let shelf: HomeNotebookShelf.Model
        let notebooks: [HomeNotebookShelf.NotebookCardModel]
    }
}
