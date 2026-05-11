import ComposableArchitecture
import XCTest
@testable import FromInk

@MainActor
final class DispatchPanelFeatureTests: XCTestCase {

    // MARK: - Tab Selection

    func test_tabSelected() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )

        await store.send(.tabSelected(.links)) {
            $0.selectedTab = .links
        }

        await store.send(.tabSelected(.calendar)) {
            $0.selectedTab = .calendar
        }
    }

    // MARK: - Visibility

    func test_presented() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )

        await store.send(.presented) {
            $0.isVisible = true
        }
    }

    func test_dismissed() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(isVisible: true),
            reducer: { DispatchPanelFeature() }
        )

        await store.send(.dismissed) {
            $0.isVisible = false
        }
    }

    // MARK: - Data Loading

    func test_headersUpdated() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )

        let headers = [
            DispatchHeaderItem(
                id: UUID(),
                ocrText: "Meeting notes",
                image: UIImage(),
                positionY: 100
            )
        ]

        await store.send(.headersUpdated(headers)) {
            $0.headers = headers
        }
    }

    func test_linksUpdated() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )

        let links = [
            DispatchLinkItem(
                id: UUID(),
                recognizedText: "Apple",
                url: URL(string: "https://apple.com")!
            )
        ]

        await store.send(.linksUpdated(links)) {
            $0.links = links
        }
    }

    func test_routedItemsLoaded() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )

        let calendarItem = DispatchRoutedItem(
            id: UUID(),
            title: "Standup",
            destination: "calendar",
            destinationURL: "",
            eventKitIdentifier: "EK-123",
            routedAt: Date(),
            isDeleted: false
        )

        let reminderItem = DispatchRoutedItem(
            id: UUID(),
            title: "Ship v0.3",
            destination: "reminders",
            destinationURL: "",
            eventKitIdentifier: "EK-456",
            routedAt: Date(),
            isDeleted: false
        )

        await store.send(
            .routedItemsLoaded(
                calendar: [calendarItem],
                reminders: [reminderItem]
            )
        ) {
            $0.calendarItems = [calendarItem]
            $0.reminderItems = [reminderItem]
        }
    }

    // MARK: - Deletion Check

    func test_deletionCheckCompleted_marksDeleted() async {
        let itemID = UUID()
        let store = TestStore(
            initialState: DispatchPanelFeature.State(
                calendarItems: [
                    DispatchRoutedItem(
                        id: itemID,
                        title: "Deleted event",
                        destination: "calendar",
                        destinationURL: "",
                        eventKitIdentifier: "EK-789",
                        routedAt: Date(),
                        isDeleted: false
                    )
                ]
            ),
            reducer: { DispatchPanelFeature() }
        )

        await store.send(.deletionCheckCompleted([itemID])) {
            $0.calendarItems[0].isDeleted = true
        }
    }

    func test_deletionCheckCompleted_ignoresUnknownIDs() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(
                calendarItems: [
                    DispatchRoutedItem(
                        id: UUID(),
                        title: "Existing event",
                        destination: "calendar",
                        destinationURL: "",
                        eventKitIdentifier: "EK-000",
                        routedAt: Date(),
                        isDeleted: false
                    )
                ]
            ),
            reducer: { DispatchPanelFeature() }
        )

        await store.send(.deletionCheckCompleted([UUID()]))
    }

    // MARK: - Forwarded Actions

    func test_headerTapped_noStateChange() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )
        await store.send(.headerTapped(UUID()))
    }

    func test_linkTapped_noStateChange() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )
        await store.send(.linkTapped(URL(string: "https://example.com")!))
    }

    func test_routedItemTapped_noStateChange() async {
        let store = TestStore(
            initialState: DispatchPanelFeature.State(),
            reducer: { DispatchPanelFeature() }
        )

        let item = DispatchRoutedItem(
            id: UUID(),
            title: "Test",
            destination: "calendar",
            destinationURL: "",
            eventKitIdentifier: nil,
            routedAt: Date(),
            isDeleted: false
        )

        await store.send(.routedItemTapped(item))
    }
}
