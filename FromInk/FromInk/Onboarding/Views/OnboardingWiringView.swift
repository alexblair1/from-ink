import ComposableArchitecture
import SwiftUI

/// Wiring view for the onboarding flow. Adapts `StoreOf<OnboardingFeature>`
/// into the container's Model, supplies the permissions confirmation
/// alert, and resolves per-step affordances:
///
/// - persistent footer (button only — no secondary link on any step,
///   permissions' old "Not now" is gone, replaced by the confirmation
///   alert)
/// - the subscription screen's top-right X close button and legal
///   chrome (Restore / Privacy / Terms)
/// - the permissions screen's row tap actions, real permission status
///   reads, and re-read on return from the system Settings app via
///   `@Environment(\.scenePhase)`
///
struct OnboardingWiringView: View {
    @Bindable var store: StoreOf<OnboardingFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let ds = DesignSystem.standard
        OnboardingContainerView(
            model: .init(
                stepBinding: Binding(
                    get: { store.step },
                    set: { newValue in
                        guard let newValue, newValue != store.step else { return }
                        store.send(.swipedToStep(newValue))
                    }
                ),
                isSwipeDisabled: store.step == .permissions,
                footer: footerModel,
                permissions: permissionsModel,
                subscription: subscriptionModel,
                backgroundColor: ds.colors.paper,
                horizontalPadding: ds.spacing.xl,
                contentTopPadding: ds.spacing.lg,
                contentBottomPadding: ds.spacing.lg,
                footerTopPadding: ds.spacing.lg,
                footerBottomPadding: ds.spacing.xl,
                close: closeButtonModel,
                closeButtonTopPadding: ds.spacing.sm
            )
        )
        // Load permission statuses when the user lands on the permissions
        // step, and re-load whenever the scene re-activates (covers the
        // return from the Settings app, where the user may have flipped
        // a toggle that we need to reflect in our UI).
        .task(id: store.step) {
            if store.step == .permissions {
                store.send(.permissionsAppeared)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && store.step == .permissions {
                store.send(.sceneBecameActive)
            }
        }
        .alert(
            AppStrings.Onboarding.permissionsConfirmationTitle,
            isPresented: Binding(
                get: { store.isPermissionsConfirmationPresented },
                set: { newValue in
                    store.send(.permissionsConfirmationBindingChanged(newValue))
                }
            )
        ) {
            Button(AppStrings.Onboarding.permissionsConfirmationConfirm) {
                store.send(.permissionsConfirmationConfirmed)
            }
            Button(AppStrings.Onboarding.permissionsConfirmationDismiss, role: .cancel) {
                store.send(.permissionsConfirmationDismissed)
            }
        } message: {
            Text(AppStrings.Onboarding.permissionsConfirmationMessage)
        }
    }

    private var footerModel: OnboardingFooter.Model {
        OnboardingFooter.Model(
            primary: OnboardingPrimaryButton.Model(
                title: primaryTitle(for: store.step),
                action: { store.send(.primaryButtonTapped) }
            ),
            secondary: nil,
            legalChrome: legalChromeModel
        )
    }

    /// Restore / Privacy / Terms link row rendered directly below the
    /// subscription primary CTA. Other steps return nil — the chrome is
    /// regulatory and only relevant at the purchase decision point.
    /// Actions are no-ops until the StoreKit + privacy/terms URL wiring
    /// lands; the UI itself is the contract here.
    private var legalChromeModel: OnboardingLegalChrome.Model? {
        guard store.step == .subscription else { return nil }
        return OnboardingLegalChrome.Model(
            onRestore: {},
            onPrivacy: {},
            onTerms: {}
        )
    }

    private var permissionsModel: OnboardingPermissionsView.Model {
        OnboardingPermissionsView.Model(
            calendarStatus: store.calendarStatus,
            remindersStatus: store.remindersStatus,
            locationStatus: store.locationStatus,
            microphoneStatus: store.microphoneStatus,
            onCalendarTap: { store.send(.calendarRowTapped) },
            onRemindersTap: { store.send(.remindersRowTapped) },
            onLocationTap: { store.send(.locationRowTapped) },
            onMicrophoneTap: { store.send(.microphoneRowTapped) }
        )
    }

    private var subscriptionModel: OnboardingSubscriptionView.Model {
        OnboardingSubscriptionView.Model(
            selectedTier: store.selectedTier,
            onTierSelected: { store.send(.tierSelected($0)) }
        )
    }

    private func primaryTitle(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:      return AppStrings.Onboarding.welcomeButton
        case .value:        return AppStrings.Onboarding.continueButton
        case .permissions:  return AppStrings.Onboarding.permissionsContinue
        case .subscription:
            // CTA label varies by selected tier (subscription EDD §5.4):
            // - Lifetime: "Buy" (matches Apple's standard non-consumable
            //   IAP button label, single word in every target language)
            // - Yearly / Monthly: "Start free trial" (accurately
            //   describes the 7-day trial action)
            return store.selectedTier == .lifetime
                ? AppStrings.Onboarding.subscriptionPrimaryLifetime
                : AppStrings.Onboarding.subscriptionPrimary
        }
    }

    private var closeButtonModel: OnboardingCloseButton.Model? {
        guard store.step == .subscription else { return nil }
        return OnboardingCloseButton.Model(action: { store.send(.secondaryLinkTapped) })
    }
}
