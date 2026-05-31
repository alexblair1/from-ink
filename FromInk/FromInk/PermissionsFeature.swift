import ComposableArchitecture
import Foundation
import UIKit
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Permissions")

/// TCA feature for the Permissions detail surface inside Settings.
///
/// Row taps follow the iOS permission-affordance pattern:
/// - `.notDetermined`: tap requests access via the iOS 17+ EventKit
///   async APIs. The system prompt appears; on resolution we re-read
///   and update the row label.
/// - Any resolved state (`.denied` / `.restricted` / `.writeOnly` /
///   `.fullAccess`): tap opens the system Settings app deep link.
///   `.fullAccess` rows could be made non-tappable, but keeping them
///   tappable (and routing to Settings) lets users revoke explicitly.
///
/// The view emits `.sceneBecameActive` when the app returns from the
/// system Settings app so the row labels refresh without the user
/// having to pop and re-push the screen.
struct PermissionsFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var calendar: PermissionAuthStatus = .notDetermined
        var reminders: PermissionAuthStatus = .notDetermined
    }

    @CasePathable
    enum Action: Equatable {
        case appeared
        case sceneBecameActive
        case statusesLoaded(calendar: PermissionAuthStatus, reminders: PermissionAuthStatus)
        case calendarRowTapped
        case remindersRowTapped
    }

    @Dependency(\.eventKitService) var eventKit

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared, .sceneBecameActive:
                return refresh()

            case .statusesLoaded(let cal, let rem):
                state.calendar = cal
                state.reminders = rem
                return .none

            case .calendarRowTapped:
                return handleTap(current: state.calendar, kind: .calendar)

            case .remindersRowTapped:
                return handleTap(current: state.reminders, kind: .reminders)
            }
        }
    }

    private enum Kind { case calendar, reminders }

    private func handleTap(
        current: PermissionAuthStatus,
        kind: Kind
    ) -> Effect<Action> {
        // notDetermined → request via the iOS 17+ EventKit API.
        // Any other state → route to system Settings; the OS owns the
        // toggles from that point on.
        if current == .notDetermined {
            return .run { send in
                let _: PermissionAuthStatus
                switch kind {
                case .calendar:  _ = await eventKit.requestEventAccess()
                case .reminders: _ = await eventKit.requestReminderAccess()
                }
                let cal = eventKit.eventAuthStatus()
                let rem = eventKit.reminderAuthStatus()
                await send(.statusesLoaded(calendar: cal, reminders: rem))
            }
        }
        return openSystemSettings()
    }

    private func refresh() -> Effect<Action> {
        .run { send in
            let cal = eventKit.eventAuthStatus()
            let rem = eventKit.reminderAuthStatus()
            await send(.statusesLoaded(calendar: cal, reminders: rem))
        }
    }

    private func openSystemSettings() -> Effect<Action> {
        .run { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
        }
    }
}
 
