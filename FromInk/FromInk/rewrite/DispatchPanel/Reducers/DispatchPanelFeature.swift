import ComposableArchitecture
import Foundation

// Manual Reducer conformance — @Reducer macro is incompatible with
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.

struct DispatchPanelFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var selectedTab: DispatchTab = .headers
        var headers: [DispatchHeaderItem] = []
        var links: [DispatchLinkItem] = []
        var calendarItems: [DispatchRoutedItem] = []
        var reminderItems: [DispatchRoutedItem] = []
        var isVisible: Bool = false
        var navigateToHeaderID: UUID? = nil
        var openLinkURL: URL? = nil
        var openRoutedItem: DispatchRoutedItem? = nil
    }

    @CasePathable
    enum Action {
        // Tab
        case tabSelected(DispatchTab)

        // Item interactions — forwarded to parent
        case headerTapped(UUID)
        case linkTapped(URL)
        case routedItemTapped(DispatchRoutedItem)

        // Lifecycle
        case presented
        case dismissed
        case deletionCheckCompleted([UUID])

        // Data loading — called by parent or on appear
        case headersUpdated([DispatchHeaderItem])
        case linksUpdated([DispatchLinkItem])
        case routedItemsLoaded(
            calendar: [DispatchRoutedItem],
            reminders: [DispatchRoutedItem]
        )
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            // MARK: - Tab

            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            // MARK: - Item interactions

            case .headerTapped(let id):
                state.navigateToHeaderID = id
                return .none

            case .linkTapped(let url):
                state.openLinkURL = url
                return .none

            case .routedItemTapped(let item):
                state.openRoutedItem = item
                return .none

            // MARK: - Lifecycle

            case .presented:
                state.isVisible = true
                return .none

            case .dismissed:
                state.isVisible = false
                return .none

            case .deletionCheckCompleted(let deletedIDs):
                for id in deletedIDs {
                    if let idx = state.calendarItems.firstIndex(where: { $0.id == id }) {
                        state.calendarItems[idx].isDeleted = true
                    }
                    if let idx = state.reminderItems.firstIndex(where: { $0.id == id }) {
                        state.reminderItems[idx].isDeleted = true
                    }
                }
                return .none

            // MARK: - Data loading

            case .headersUpdated(let headers):
                state.headers = headers
                return .none

            case .linksUpdated(let links):
                state.links = links
                return .none

            case .routedItemsLoaded(let calendar, let reminders):
                state.calendarItems = calendar
                state.reminderItems = reminders
                return .none
            }
        }
    }
}
