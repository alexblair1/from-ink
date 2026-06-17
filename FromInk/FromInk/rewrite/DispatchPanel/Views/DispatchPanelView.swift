import SwiftUI

/// Feature view for the dispatch panel. No TCA imports.
/// Composes component views from a flat Model.
///
struct DispatchPanelView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            tabBar
            content
            if let action = model.action {
                DispatchActionBarButton(model: action)
            }
        }
        .background(model.background)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            MonoLabel(model.title)
            Spacer()
            Button(action: model.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: model.dismissIconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.secondaryColor)
                    .frame(
                        width: model.dismissHitTarget,
                        height: model.dismissHitTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, model.horizontalPadding)
        .frame(height: model.titleBarHeight)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(model.tabs, id: \.id) { tab in
                DispatchTabButton(model: tab)
            }
        }
        .frame(height: model.tabBarHeight)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if model.activeContent.isEmpty {
                DispatchEmptyState(model: model.emptyState)
            } else {
                scrollableList(model.activeContent.rowItems)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollableList(_ items: [RowItem]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case .header(let m):
                        DispatchHeaderRow(model: m)
                    case .link(let m):
                        DispatchLinkRow(model: m)
                    case .routedItem(let m):
                        DispatchRoutedItemRow(model: m)
                    }
                    HairlineRule()
                        .padding(.leading, model.horizontalPadding)
                }
            }
        }
    }
}

// MARK: - Model

extension DispatchPanelView {
    struct Model {
        let title: String
        let tabs: [DispatchTabButton.Model]
        let activeContent: ContentKind
        let emptyState: DispatchEmptyState.Model
        let action: DispatchActionBarButton.Model?
        let onDismiss: () -> Void
        let background: Color
        let secondaryColor: Color
        let horizontalPadding: CGFloat
        let titleBarHeight: CGFloat
        let tabBarHeight: CGFloat
        let dismissIconSize: CGFloat
        let dismissHitTarget: CGFloat
    }

    enum ContentKind {
        case headers([DispatchHeaderRow.Model])
        case links([DispatchLinkRow.Model])
        case routedItems([DispatchRoutedItemRow.Model])

        var isEmpty: Bool {
            switch self {
            case .headers(let rows): rows.isEmpty
            case .links(let rows): rows.isEmpty
            case .routedItems(let rows): rows.isEmpty
            }
        }

        var rowItems: [RowItem] {
            switch self {
            case .headers(let rows): rows.map { .header($0) }
            case .links(let rows): rows.map { .link($0) }
            case .routedItems(let rows): rows.map { .routedItem($0) }
            }
        }
    }

    enum RowItem: Identifiable {
        case header(DispatchHeaderRow.Model)
        case link(DispatchLinkRow.Model)
        case routedItem(DispatchRoutedItemRow.Model)

        var id: String {
            switch self {
            case .header(let m): "header-\(m.id)"
            case .link(let m): "link-\(m.id)"
            case .routedItem(let m): "routed-\(m.id)"
            }
        }
    }
}

// MARK: - Model init

extension DispatchPanelView.Model {
    init(
        title: String,
        tabs: [DispatchTabButton.Model],
        activeContent: DispatchPanelView.ContentKind,
        emptyState: DispatchEmptyState.Model,
        action: DispatchActionBarButton.Model?,
        onDismiss: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.title = title
        self.tabs = tabs
        self.activeContent = activeContent
        self.emptyState = emptyState
        self.action = action
        self.onDismiss = onDismiss
        self.background = ds.colors.paper
        self.secondaryColor = ds.colors.ink2
        self.horizontalPadding = ds.spacing.base
        self.titleBarHeight = ds.layout.navBarHeight
        self.tabBarHeight = ds.layout.dispatchTabBarHeight
        self.dismissIconSize = ds.layout.dismissIconSize
        self.dismissHitTarget = ds.layout.dismissHitTarget
    }
}
