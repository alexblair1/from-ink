import SwiftUI

/// Feature view for the dispatch panel. No TCA imports.
/// Composes component views from a flat Model.
///
struct DispatchPanelView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HairlineRule()
            tabBar
            HairlineRule()
            content
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
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                DispatchTabButton(model: tab)

                if index < model.tabs.count - 1 {
                    HairlineRule(.vertical)
                }
            }
        }
        .frame(height: model.tabBarHeight)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            switch model.activeContent {
            case .headers(let rows) where rows.isEmpty:
                DispatchEmptyState(
                    model: .init(message: AppStrings.Dispatch.emptyHeaders)
                )

            case .headers(let rows):
                scrollableList(rows.map { .header($0) })

            case .links(let rows) where rows.isEmpty:
                DispatchEmptyState(
                    model: .init(message: AppStrings.Dispatch.emptyLinks)
                )

            case .links(let rows):
                scrollableList(rows.map { .link($0) })

            case .routedItems(let rows, let emptyMessage) where rows.isEmpty:
                DispatchEmptyState(model: .init(message: emptyMessage))

            case .routedItems(let rows, _):
                scrollableList(rows.map { .routedItem($0) })
            }
        }
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
        case routedItems([DispatchRoutedItemRow.Model], emptyMessage: String)
    }

    private enum RowItem: Identifiable {
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
        onDismiss: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.title = title
        self.tabs = tabs
        self.activeContent = activeContent
        self.onDismiss = onDismiss
        self.background = ds.colors.paper
        self.secondaryColor = ds.colors.ink2
        self.horizontalPadding = ds.spacing.base
        self.titleBarHeight = ds.layout.navBarHeight
        self.tabBarHeight = ds.layout.hitTarget
        self.dismissIconSize = ds.layout.dismissIconSize
        self.dismissHitTarget = ds.layout.dismissHitTarget
    }
}
