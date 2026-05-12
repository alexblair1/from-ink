import SwiftUI

/// Sticky top bar: weather icon (left), wordmark (center), compose button (right).
/// Component view — no TCA imports.
///
struct HomeTopBar: View {
    let model: Model

    var body: some View {
        HStack {
            Button(action: model.onSettings) {
                Image(systemName: model.leadingIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(model.title)
                .font(model.titleFont)
                .italic()
                .foregroundStyle(model.titleColor)
                .tracking(model.titleTracking)

            Spacer()

            Button(action: model.onCompose) {
                Image(systemName: model.trailingIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.topPadding)
        .padding(.bottom, model.bottomPadding)
    }
}

// MARK: - Model

extension HomeTopBar {
    struct Model {
        let title: String
        let leadingIcon: String
        let trailingIcon: String
        let onSettings: () -> Void
        let onCompose: () -> Void
        let titleFont: Font
        let titleColor: Color
        let titleTracking: CGFloat
        let iconColor: Color
        let iconSize: CGFloat
        let hitTarget: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }
}

// MARK: - Model init

extension HomeTopBar.Model {
    init(
        onSettings: @escaping () -> Void,
        onCompose: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.title = AppStrings.Home.title
        self.leadingIcon = "sun.max"
        self.trailingIcon = "square.and.pencil"
        self.onSettings = onSettings
        self.onCompose = onCompose
        self.titleFont = .system(size: 18, weight: .regular, design: .serif)
        self.titleColor = ds.colors.ink
        self.titleTracking = 0.4
        self.iconColor = ds.colors.ink
        self.iconSize = 17
        self.hitTarget = ds.layout.hitTarget
        self.horizontalPadding = ds.spacing.lg
        self.topPadding = ds.spacing.sm
        self.bottomPadding = ds.spacing.xs
    }
}
