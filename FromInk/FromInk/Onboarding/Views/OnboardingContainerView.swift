import SwiftUI

/// Onboarding shell.
///
/// Layout, top to bottom:
///
///                                       ╳ ← close button (subscription only)
///     ┌─────────────────────────────────────┐
///     │                                     │
///     │   horizontal paging ScrollView      │
///     │   each page hosts a vertical        │
///     │   ScrollView so AX content can      │
///     │   grow + scroll within its page     │
///     │                                     │
///     ├─────────────────────────────────────┤
///     │   ┌─────────────────────────────┐   │
///     │   │ Primary CTA  →              │   │  ← single view identity
///     │   └─────────────────────────────┘   │
///     │           (reserved zone)           │  ← min-height spacer
///     └─────────────────────────────────────┘
///
/// The footer's primary button stays at a constant Y across all four
/// steps with a single SwiftUI view identity — only its `title` and
/// `action` change. No secondary footer link or note exists on any
/// screen; the reserved zone below the button is an empty min-height
/// spacer (forced to render via `maxWidth: .infinity`) so the CTA's
/// vertical offset stays consistent across welcome, value, permissions,
/// and subscription.
///
/// **Subscription-only dismiss**: the X close button rendered at the
/// top-right replaces the older "Maybe later" footer link. Tapping it
/// completes onboarding.
///
/// **Permissions guard rail**: there is no "Not now" affordance on the
/// permissions screen. Tapping Continue with both toggles still off
/// triggers a one-shot confirmation alert ("Without these, the brief
/// stays quiet") — the user must explicitly opt in or opt out.
///
/// **Swipe gating**: while on `.permissions`, the horizontal ScrollView
/// is disabled. The user cannot drag the page in either direction; they
/// must tap Continue. Programmatic step changes via the scrollPosition
/// binding still scroll, so the buttons still navigate.
///
/// **Per-page vertical scroll**: every page wraps its content in a
/// vertical ScrollView. At default Dynamic Type sizes the content fits
/// and the scroll is dormant; at AX5 the content overflows and the
/// vertical scroll engages, while the pinned footer stays put.
///
struct OnboardingContainerView: View {

    let model: Model

    var body: some View {
        ZStack {
            model.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(OnboardingStep.allCases) { step in
                            page(for: step)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(step)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: model.stepBinding)
                .scrollDisabled(model.isSwipeDisabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingFooter(model: model.footer)
                    .padding(.horizontal, model.horizontalPadding)
                    .padding(.top, model.footerTopPadding)
                    .padding(.bottom, model.footerBottomPadding)
                    .frame(maxWidth: .infinity)
                    .background(model.backgroundColor)
            }
        }
    }

    /// Top "toolbar" zone. When the container has a close button, this
    /// reserves the close button's slot above the swipeable content
    /// area, so headline text never wraps into the same horizontal lane
    /// as the X. When the container has no close button (welcome, value,
    /// permissions), this branch renders nothing and the content area
    /// extends to the top safe area.
    @ViewBuilder
    private var topBar: some View {
        if let close = model.close {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingCloseButton(model: close)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.top, model.closeButtonTopPadding)
        }
    }

    @ViewBuilder
    private func page(for step: OnboardingStep) -> some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: model.contentTopPadding)
                    screen(for: step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, model.horizontalPadding)
                    Spacer(minLength: model.contentBottomPadding)
                }
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func screen(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView(model: .init())
        case .value:
            OnboardingValueView(model: .init())
        case .permissions:
            OnboardingPermissionsView(model: model.permissions)
        case .subscription:
            OnboardingSubscriptionView(model: .init())
        }
    }
}

// MARK: - Model

extension OnboardingContainerView {
    struct Model {
        let stepBinding: Binding<OnboardingStep?>
        let isSwipeDisabled: Bool
        let footer: OnboardingFooter.Model
        let permissions: OnboardingPermissionsView.Model
        let backgroundColor: Color
        let horizontalPadding: CGFloat
        let contentTopPadding: CGFloat
        let contentBottomPadding: CGFloat
        let footerTopPadding: CGFloat
        let footerBottomPadding: CGFloat
        /// Optional X close button rendered in the container's top
        /// toolbar slot. Present only on the subscription step. When
        /// non-nil, the toolbar reserves vertical space above the
        /// swipeable content area; when nil, no toolbar is rendered.
        let close: OnboardingCloseButton.Model?
        let closeButtonTopPadding: CGFloat
    }
}
