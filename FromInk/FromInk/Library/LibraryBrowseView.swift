import ComposableArchitecture
import SwiftUI

/// Full-screen browse surface — title bar + dismiss + the reusable
/// `LibrarySearchWiringView` body. This is the first consumer of
/// `LibrarySearchFeature`; the future notebook picker and quick-
/// switcher will wrap the same wiring view with different chrome.
///
/// **Presentation:** lives behind a `.sheet(item:)` or
/// `.fullScreenCover(item:)` on the parent. The wrapping surface owns
/// the dismiss path (clears the parent's `@Presents` optional); this
/// view dispatches an `onDismiss` closure from the wiring view's
/// Model.
///
struct LibraryBrowseView: View {
    let store: StoreOf<LibrarySearchFeature>
    let onDismiss: () -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineRule()
            LibrarySearchWiringView(store: store)
        }
        .background(ds.colors.paper)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(AppStrings.LibrarySearch.browseTitle)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(ds.colors.ink2)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: ds.layout.dismissIconSize, weight: .regular))
                    .foregroundStyle(ds.colors.ink2)
                    .frame(width: ds.layout.dismissHitTarget, height: ds.layout.dismissHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.LibrarySearch.dismissAction)
        }
        .padding(.horizontal, ds.spacing.sm)
        .frame(height: ds.spacing.xxl)
    }
}
