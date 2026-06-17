import SwiftUI
import ComposableArchitecture

/// Wiring view for the dispatch panel.
/// Contains zero layout — exactly one expression in the body.
///
// TODO: Does this all scale? How easy can we add tabs in the dispatch view?
struct DispatchPanelWiringView: View {
    let store: StoreOf<DispatchPanelFeature>

    var body: some View {
        DispatchPanelView(model: .init(store: store))
    }
}

// MARK: - Adapter

extension DispatchPanelView.Model {
    init(store: StoreOf<DispatchPanelFeature>) {
        let ds = DesignSystem.standard
        let tabs = DispatchTab.allCases.map { tab in
            let isSelected = store.selectedTab == tab
            return DispatchTabButton.Model(
                id: tab.rawValue,
                icon: tab.icon,
                onTap: { store.send(.tabSelected(tab)) },
                foreground: isSelected ? ds.colors.paperPure : ds.colors.inkPure,
                background: isSelected ? ds.colors.inkPure : .clear
            )
        }

        let activeContent: DispatchPanelView.ContentKind = {
            switch store.selectedTab {
            case .headers:
                let rows = store.headers
                    .sorted { $0.positionY < $1.positionY }
                    .map { header in
                        DispatchHeaderRow.Model(
                            id: header.id.uuidString,
                            ocrText: header.ocrText,
                            image: header.image,
                            onTap: { store.send(.headerTapped(header.id)) }
                        )
                    }
                return .headers(rows)

            case .links:
                let rows = store.links.map { link in
                    DispatchLinkRow.Model(
                        id: link.id.uuidString,
                        recognizedText: link.recognizedText,
                        url: link.url,
                        onTap: { store.send(.linkTapped(link.url)) }
                    )
                }
                return .links(rows)

            case .calendar:
                let rows = store.calendarItems.map { item in
                    DispatchRoutedItemRow.Model(
                        item: item,
                        onTap: { store.send(.routedItemTapped(item)) }
                    )
                }
                return .routedItems(rows)

            case .reminders:
                let rows = store.reminderItems.map { item in
                    DispatchRoutedItemRow.Model(
                        item: item,
                        onTap: { store.send(.routedItemTapped(item)) }
                    )
                }
                return .routedItems(rows)
            }
        }()

        let tab = store.selectedTab
        let emptyState = DispatchEmptyState.Model(
            icon: tab.icon,
            headline: tab.emptyHeadline,
            hint: tab.emptyHint
        )

        // Headers are authored on the page, so they carry no add label
        // and the action bar is omitted for that tab.
        let action = tab.addLabel.map { label in
            DispatchActionBarButton.Model(
                label: label,
                onTap: { store.send(.addTapped(tab)) }
            )
        }

        self.init(
            title: tab.title,
            tabs: tabs,
            activeContent: activeContent,
            emptyState: emptyState,
            action: action,
            onDismiss: { store.send(.dismissed) }
        )
    }
}
