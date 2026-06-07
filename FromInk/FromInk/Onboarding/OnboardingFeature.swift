import ComposableArchitecture
import UIKit

/// Drives the onboarding flow.
///
/// State tracks the current step, real permission statuses (calendar /
/// reminders via EventKit, microphone via AVAudioApplication), and a
/// confirmation flag for the "you didn't enable anything" prompt.
///
/// Advancement model:
/// - `primaryButtonTapped`: usually advances. **Special case** on
///   `.permissions`: if neither calendar nor reminders grants read
///   access, we present the confirmation alert. If at least one grants
///   read, we accept the user's choice and advance.
/// - `secondaryLinkTapped`: fired only by the subscription screen's
///   top-right X close button. On the final step, marks
///   `hasSeenOnboarding = true` and emits `.delegate(.completed)`.
/// - `swipedToStep`: paging swipe — accept the new step verbatim.
///
/// Permission row taps follow the iOS affordance pattern (mirrored from
/// `PermissionsFeature` in Settings):
/// - `.notDetermined`: tap requests via the iOS 17+ EventKit /
///   AVAudioApplication APIs. The system prompt appears; on resolution
///   we re-read and update the row.
/// - Any resolved non-granted state (`.denied` / `.restricted` /
///   `.writeOnly` for EventKit, `.denied` for microphone): tap opens
///   the system Settings deep link.
/// - `.fullAccess` / `.granted`: tap also opens Settings so the user
///   can explicitly revoke.
///
/// `sceneBecameActive` is emitted from the wiring view via
/// `@Environment(\.scenePhase)` so that statuses refresh automatically
/// when the user returns from the Settings app.
///
/// The `hasSeenOnboarding` flag is intentionally written **only** when
/// the user reaches the end of the flow — backing out, force-quitting,
/// or failing the boot replays onboarding.
///
struct OnboardingFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var step: OnboardingStep = .welcome
        var calendarStatus: PermissionAuthStatus = .notDetermined
        var remindersStatus: PermissionAuthStatus = .notDetermined
        var locationStatus: LocationAuthStatus = .notDetermined
        var microphoneStatus: MicrophoneAuthStatus = .notDetermined
        /// `true` while the "you didn't enable anything" confirmation
        /// alert is presented. Only set when the user taps Continue on
        /// permissions with both calendar and reminders ungranted.
        var isPermissionsConfirmationPresented: Bool = false

        /// Either EventKit permission grants read access. Drives the
        /// confirmation gate on Continue. Location and microphone
        /// don't participate — location is a brief garnish (weather),
        /// microphone is for a separate post-onboarding feature.
        var hasAnyEventKitRead: Bool {
            calendarStatus.grantsRead || remindersStatus.grantsRead
        }
    }

    @CasePathable
    enum Action {
        case primaryButtonTapped
        case secondaryLinkTapped
        case swipedToStep(OnboardingStep)
        case calendarRowTapped
        case remindersRowTapped
        case locationRowTapped
        case microphoneRowTapped
        case permissionsAppeared
        case sceneBecameActive
        case statusesLoaded(
            calendar: PermissionAuthStatus,
            reminders: PermissionAuthStatus,
            location: LocationAuthStatus,
            microphone: MicrophoneAuthStatus
        )
        case permissionsConfirmationConfirmed
        case permissionsConfirmationDismissed
        case permissionsConfirmationBindingChanged(Bool)
        case completionPersisted
        case delegate(Delegate)

        enum Delegate: Equatable {
            case completed
        }
    }

    @Dependency(\.userPreferences) var userPreferences
    @Dependency(\.eventKitService) var eventKit
    @Dependency(\.microphoneService) var microphone
    @Dependency(\.locationService) var location

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // Permissions: if user tries to advance with neither calendar
            // nor reminders granted, gate behind the confirmation alert.
            case .primaryButtonTapped where state.step == .permissions
                && !state.hasAnyEventKitRead:
                state.isPermissionsConfirmationPresented = true
                return .none

            case .primaryButtonTapped where state.step.next != nil:
                state.step = state.step.next!
                return .none

            case .primaryButtonTapped:
                return .run { send in
                    await userPreferences.markOnboardingCompleted()
                    await send(.completionPersisted)
                }

            case .secondaryLinkTapped where state.step.next != nil:
                state.step = state.step.next!
                return .none

            case .secondaryLinkTapped:
                return .run { send in
                    await userPreferences.markOnboardingCompleted()
                    await send(.completionPersisted)
                }

            case .calendarRowTapped:
                return handleEventKitTap(
                    current: state.calendarStatus,
                    kind: .calendar,
                    routedFrom: state.step
                )

            case .remindersRowTapped:
                return handleEventKitTap(
                    current: state.remindersStatus,
                    kind: .reminders,
                    routedFrom: state.step
                )

            case .locationRowTapped:
                return handleLocationTap(
                    current: state.locationStatus,
                    routedFrom: state.step
                )

            case .microphoneRowTapped:
                return handleMicrophoneTap(
                    current: state.microphoneStatus,
                    routedFrom: state.step
                )

            case .permissionsAppeared:
                return refreshStatuses()

            case .sceneBecameActive:
                // The user is back from somewhere — most commonly the
                // system Settings app after we routed them there to grant
                // a permission. Clear the saved-step marker so a
                // subsequent user-initiated kill returns them to welcome
                // (the marker's only purpose is to survive the Settings
                // round-trip; once they're back, it's no longer needed).
                return .merge(
                    refreshStatuses(),
                    .run { _ in await userPreferences.saveOnboardingStep(nil) }
                )

            case .statusesLoaded(let cal, let rem, let loc, let mic):
                state.calendarStatus = cal
                state.remindersStatus = rem
                state.locationStatus = loc
                state.microphoneStatus = mic
                return .none

            case .permissionsConfirmationConfirmed:
                state.isPermissionsConfirmationPresented = false
                let calStatus = state.calendarStatus
                let remStatus = state.remindersStatus
                // "Turn on both" — request anything still notDetermined,
                // open Settings if anything is in a state we can't change
                // programmatically. Statuses re-load on return from
                // Settings via sceneBecameActive.
                return .run { send in
                    if calStatus == .notDetermined {
                        _ = await eventKit.requestEventAccess()
                    }
                    if remStatus == .notDetermined {
                        _ = await eventKit.requestReminderAccess()
                    }
                    let cal = eventKit.eventAuthStatus()
                    let rem = eventKit.reminderAuthStatus()
                    let loc = await location.status()
                    let mic = await microphone.status()
                    await send(.statusesLoaded(
                        calendar: cal, reminders: rem, location: loc, microphone: mic
                    ))
                    if cal.requiresSettings || rem.requiresSettings {
                        await openSystemSettings()
                    }
                }

            case .permissionsConfirmationDismissed:
                state.isPermissionsConfirmationPresented = false
                if let next = state.step.next { state.step = next }
                return .none

            case .permissionsConfirmationBindingChanged(let isPresented):
                state.isPermissionsConfirmationPresented = isPresented
                return .none

            case .swipedToStep(let next):
                state.step = next
                return .none

            case .completionPersisted:
                return .send(.delegate(.completed))

            case .delegate:
                return .none
            }
        }
    }

    private enum EventKitKind { case calendar, reminders }

    private func handleEventKitTap(
        current: PermissionAuthStatus,
        kind: EventKitKind,
        routedFrom step: OnboardingStep
    ) -> Effect<Action> {
        // notDetermined → request via the iOS 17+ EventKit API.
        // Anything else (including .fullAccess so users can revoke) →
        // open the system Settings app.
        if current == .notDetermined {
            return .run { send in
                switch kind {
                case .calendar:  _ = await eventKit.requestEventAccess()
                case .reminders: _ = await eventKit.requestReminderAccess()
                }
                let cal = eventKit.eventAuthStatus()
                let rem = eventKit.reminderAuthStatus()
                let loc = await location.status()
                let mic = await microphone.status()
                await send(.statusesLoaded(
                    calendar: cal, reminders: rem, location: loc, microphone: mic
                ))
            }
        }
        return openSettings(routedFrom: step)
    }

    private func handleMicrophoneTap(
        current: MicrophoneAuthStatus,
        routedFrom step: OnboardingStep
    ) -> Effect<Action> {
        if current == .notDetermined {
            return .run { send in
                _ = await microphone.requestAccess()
                let cal = eventKit.eventAuthStatus()
                let rem = eventKit.reminderAuthStatus()
                let loc = await location.status()
                let mic = await microphone.status()
                await send(.statusesLoaded(
                    calendar: cal, reminders: rem, location: loc, microphone: mic
                ))
            }
        }
        return openSettings(routedFrom: step)
    }

    private func handleLocationTap(
        current: LocationAuthStatus,
        routedFrom step: OnboardingStep
    ) -> Effect<Action> {
        if current == .notDetermined {
            return .run { send in
                _ = await location.requestAccess()
                let cal = eventKit.eventAuthStatus()
                let rem = eventKit.reminderAuthStatus()
                let loc = await location.status()
                let mic = await microphone.status()
                await send(.statusesLoaded(
                    calendar: cal, reminders: rem, location: loc, microphone: mic
                ))
            }
        }
        return openSettings(routedFrom: step)
    }

    private func refreshStatuses() -> Effect<Action> {
        .run { send in
            let cal = eventKit.eventAuthStatus()
            let rem = eventKit.reminderAuthStatus()
            let loc = await location.status()
            let mic = await microphone.status()
            await send(.statusesLoaded(
                calendar: cal, reminders: rem, location: loc, microphone: mic
            ))
        }
    }

    /// Persists the step the user is being routed away from, then opens
    /// the system Settings app. This persistence call is the **only**
    /// time the onboarding step is written to disk — user-initiated kills
    /// mid-onboarding never persist, so relaunching after force-quit
    /// always lands at welcome. The marker is cleared on
    /// `.sceneBecameActive` once the user has returned, and again
    /// defensively on `markOnboardingCompleted`.
    private func openSettings(routedFrom step: OnboardingStep) -> Effect<Action> {
        .run { _ in
            await userPreferences.saveOnboardingStep(step)
            await openSystemSettings()
        }
    }

    @MainActor
    private func openSystemSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }
}
