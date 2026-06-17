import SwiftUI

/// Empty state for a dispatch panel tab.
/// A circular icon badge over a serif-italic headline and a mono
/// uppercase hint. Component view — no TCA imports.
///
struct DispatchEmptyState: View {
    let model: Model

    var body: some View {
        VStack(spacing: model.badgeToTextSpacing) {
            Spacer()

            ZStack {
                Circle().fill(model.badgeBackground)
                Image(systemName: model.icon)
                    .font(.system(size: model.badgeIconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.badgeIconColor)
            }
            .frame(width: model.badgeDiameter, height: model.badgeDiameter)

            VStack(spacing: model.headlineToHintSpacing) {
                Text(model.headline)
                    .font(model.headlineFont)
                    .foregroundStyle(model.headlineColor)
                    .multilineTextAlignment(.center)

                Text(model.hint)
                    .font(model.hintFont)
                    .tracking(model.hintTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(model.hintColor)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, model.horizontalPadding)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Model

extension DispatchEmptyState {
    struct Model {
        let icon: String
        let headline: String
        let hint: String
        let badgeBackground: Color
        let badgeIconColor: Color
        let headlineColor: Color
        let hintColor: Color
        let headlineFont: Font
        let hintFont: Font
        let hintTracking: CGFloat
        let badgeDiameter: CGFloat
        let badgeIconSize: CGFloat
        let badgeToTextSpacing: CGFloat
        let headlineToHintSpacing: CGFloat
        let horizontalPadding: CGFloat
    }
}

// MARK: - Model init

extension DispatchEmptyState.Model {
    init(
        icon: String,
        headline: String,
        hint: String,
        ds: DesignSystem = .standard
    ) {
        self.icon = icon
        self.headline = headline
        self.hint = hint
        self.badgeBackground = ds.colors.surface
        self.badgeIconColor = ds.colors.ink3
        self.headlineColor = ds.colors.ink3
        self.hintColor = ds.colors.ink3
        self.headlineFont = ds.typography.editorBody.italic()
        self.hintFont = ds.typography.monoSmall
        self.hintTracking = ds.typography.monoLinkTracking
        self.badgeDiameter = ds.layout.dispatchEmptyBadgeDiameter
        self.badgeIconSize = ds.layout.dispatchEmptyBadgeIconSize
        self.badgeToTextSpacing = ds.spacing.base
        self.headlineToHintSpacing = ds.spacing.sm
        self.horizontalPadding = ds.spacing.xl
    }
}
