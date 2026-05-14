import SwiftUI

/// The home screen — composes sticky header, daily brief, and notebook shelf.
/// Feature view — no TCA imports.
///
struct HomeScreenView: View {
    let model: Model
    @Binding var searchText: String
    @Binding var isBriefExpanded: Bool

    @State private var stickyHeaderHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            model.backgroundColor.ignoresSafeArea()

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

                    if let emptyState = model.emptyState {
                        HomeEmptyState(model: emptyState)
                    }

                    Spacer().frame(height: model.bottomSpacing)
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
            .background(model.backgroundColor)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                stickyHeaderHeight = height
            }
        }
    }
}

// MARK: - Model

extension HomeScreenView {
    struct Model {
        let topBar: HomeTopBar.Model
        let dailyBrief: HomeDailyBrief.Model
        let shelf: HomeNotebookShelf.Model
        let notebooks: [HomeNotebookShelf.NotebookCardModel]
        let emptyState: HomeEmptyState.Model?
        let backgroundColor: Color
        let bottomSpacing: CGFloat
    }
}

// MARK: - Model init

extension HomeScreenView.Model {
    init(
        topBar: HomeTopBar.Model,
        dailyBrief: HomeDailyBrief.Model,
        shelf: HomeNotebookShelf.Model,
        notebooks: [HomeNotebookShelf.NotebookCardModel],
        emptyState: HomeEmptyState.Model? = nil,
        ds: DesignSystem = .standard
    ) {
        self.topBar = topBar
        self.dailyBrief = dailyBrief
        self.shelf = shelf
        self.notebooks = notebooks
        self.emptyState = emptyState
        self.backgroundColor = ds.colors.paper
        self.bottomSpacing = ds.spacing.xxl
    }
}
