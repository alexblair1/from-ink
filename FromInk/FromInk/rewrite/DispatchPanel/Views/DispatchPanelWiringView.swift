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
                foreground: isSelected ? ds.colors.ink : ds.colors.ink3,
                background: isSelected ? ds.colors.highlight : .clear,
                indicatorColor: isSelected ? ds.colors.ink : .clear,
                indicatorHeight: isSelected
                    ? ds.layout.toolbarActiveIndicatorWidth
                    : 0
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
                return .routedItems(
                    rows,
                    emptyMessage: AppStrings.Dispatch.emptyCalendar
                )

            case .reminders:
                let rows = store.reminderItems.map { item in
                    DispatchRoutedItemRow.Model(
                        item: item,
                        onTap: { store.send(.routedItemTapped(item)) }
                    )
                }
                return .routedItems(
                    rows,
                    emptyMessage: AppStrings.Dispatch.emptyReminders
                )
            }
        }()

        self.init(
            title: store.selectedTab.title,
            tabs: tabs,
            activeContent: activeContent,
            onDismiss: { store.send(.dismissed) }
        )
    }
}
