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
/// view dispatches an `onDismiss` closure carried on the Chrome Model.
///
/// Tokens are resolved in `Chrome.Model.init` — no `DesignSystem`
/// reads in the view body, no magic numbers (per CLAUDE.md "Code
/// Styling").
///
struct LibraryBrowseView: View {
    let store: StoreOf<LibrarySearchFeature>
    let chrome: Chrome

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineRule()
            LibrarySearchWiringView(store: store)
        }
        .background(chrome.background)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(chrome.title)
                .font(chrome.titleFont)
                .foregroundStyle(chrome.titleColor)
            Spacer(minLength: 0)
            Button(action: chrome.onDismiss) {
                Image(systemName: chrome.dismissIconSystemName)
                    .font(.system(size: chrome.dismissIconSize, weight: .regular))
                    .foregroundStyle(chrome.dismissIconColor)
                    .frame(width: chrome.dismissFrame, height: chrome.dismissFrame)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chrome.dismissAccessibilityLabel)
        }
        .padding(.horizontal, chrome.headerHorizontalPadding)
        .frame(height: chrome.headerHeight)
    }
}

// MARK: - Chrome model

extension LibraryBrowseView {
    /// Pre-resolved chrome values. Built at the call site so the view
    /// body reads flat fields, never `DesignSystem.standard` directly.
    struct Chrome {
        let title: String
        let onDismiss: () -> Void
        let dismissAccessibilityLabel: String
        let dismissIconSystemName: String

        let background: Color
        let titleFont: Font
        let titleColor: Color
        let dismissIconColor: Color
        let dismissIconSize: CGFloat
        let dismissFrame: CGFloat
        let headerHeight: CGFloat
        let headerHorizontalPadding: CGFloat
    }
}

extension LibraryBrowseView.Chrome {
    init(
        onDismiss: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.title = AppStrings.LibrarySearch.browseTitle
        self.onDismiss = onDismiss
        self.dismissAccessibilityLabel = AppStrings.LibrarySearch.dismissAction
        self.dismissIconSystemName = "xmark"

        self.background = ds.colors.paper
        self.titleFont = .system(size: 14, weight: .medium, design: .monospaced)
        self.titleColor = ds.colors.ink2
        self.dismissIconColor = ds.colors.ink2
        self.dismissIconSize = ds.layout.dismissIconSize
        self.dismissFrame = ds.layout.dismissHitTarget
        self.headerHeight = ds.spacing.xxl
        self.headerHorizontalPadding = ds.spacing.sm
    }
}
