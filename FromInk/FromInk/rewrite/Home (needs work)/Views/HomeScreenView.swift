import SwiftUI

/// The home screen — composes sticky header, daily brief, and notebook shelf.
/// Feature view — no TCA imports.
///
struct HomeScreenView: View {
    let model: Model
    @Binding var searchText: String

    @State private var stickyHeaderHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            model.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: stickyHeaderHeight)

                    HomeDailyBrief(model: model.dailyBrief)

                    Group {
                        if !model.notebooks.isEmpty {
                            HomeNotebookShelf(model: model.shelf)
                        }

                        if let emptyState = model.emptyState {
                            HomeEmptyState(model: emptyState)
                        }
                    }
                    // 24pt gap between the brief section and the
                    // notebooks shelf so the major editorial blocks
                    // breathe consistently with the gaps inside the
                    // brief itself.
                    .padding(.top, model.majorSectionSpacing)
                    .opacity(model.nonFocalOpacity)
                    .allowsHitTesting(model.nonFocalIsInteractive)
                    .accessibilityHidden(!model.nonFocalIsInteractive)
                    .overlay(scrimOverlay(action: model.onScrimTap))

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
            .opacity(model.nonFocalOpacity)
            .allowsHitTesting(model.nonFocalIsInteractive)
            .accessibilityHidden(!model.nonFocalIsInteractive)
            .overlay(scrimOverlay(action: model.onScrimTap))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                stickyHeaderHeight = height
            }
        }
    }

    /// Transparent tap-target overlay used to dismiss the wheel when the user
    /// taps a faded (non-focal) area. Returns an empty view when no scrim
    /// action is supplied.
    @ViewBuilder
    private func scrimOverlay(action: (() -> Void)?) -> some View {
        if let action {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { action() }
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
        /// Vertical gap between major top-level sections (brief → notebooks).
        let majorSectionSpacing: CGFloat
        /// Opacity for sections outside the wheel's focus (top bar, shelf,
        /// empty state). `1.0` normally; `~0.10` when the wheel is open.
        let nonFocalOpacity: Double
        /// Whether non-focal sections accept hit-testing. Disabled while the
        /// wheel is open so taps don't fall through to faded notebooks/etc.
        let nonFocalIsInteractive: Bool
        /// Action fired when the user taps a faded non-focal area to
        /// dismiss the wheel. `nil` when the wheel is closed.
        let onScrimTap: (() -> Void)?
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
        nonFocalOpacity: Double = 1.0,
        nonFocalIsInteractive: Bool = true,
        onScrimTap: (() -> Void)? = nil,
        ds: DesignSystem = .standard
    ) {
        self.topBar = topBar
        self.dailyBrief = dailyBrief
        self.shelf = shelf
        self.notebooks = notebooks
        self.emptyState = emptyState
        self.backgroundColor = ds.colors.paper
        self.bottomSpacing = ds.spacing.xxl
        self.majorSectionSpacing = ds.spacing.lg
        self.nonFocalOpacity = nonFocalOpacity
        self.nonFocalIsInteractive = nonFocalIsInteractive
        self.onScrimTap = onScrimTap
    }
}
