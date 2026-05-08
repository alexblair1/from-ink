import SwiftUI

/// Bottom tab bar with SF Symbol icons and mono labels.
/// Uses regular material background with top hairline rule.
///
///     InkTabBar(
///         tabs: [
///             .init(icon: "house", label: "Home"),
///             .init(icon: "book.closed", label: "Library"),
///             .init(icon: "tray", label: "Dispatch"),
///             .init(icon: "gearshape", label: "Settings"),
///         ],
///         selectedIndex: $selected
///     )
///
struct InkTabBar: View {

    let tabs: [Tab]
    @Binding var selectedIndex: Int
    let style: Style

    init(
        tabs: [Tab],
        selectedIndex: Binding<Int>,
        style: Style = .standard
    ) {
        self.tabs = tabs
        self._selectedIndex = selectedIndex
        self.style = style
    }

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let isSelected = selectedIndex == index

                    Button {
                        selectedIndex = index
                    } label: {
                        VStack(spacing: style.innerSpacing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: style.iconSize, weight: isSelected ? .medium : .regular))
                                .symbolRenderingMode(.monochrome)

                            Text(tab.label)
                                .font(style.labelFont)
                                .tracking(10 * 0.18)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(isSelected ? style.selectedColor : style.unselectedColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, style.verticalPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, style.horizontalPadding)
        }
        .background(.regularMaterial)
    }
}

extension InkTabBar {
    struct Style {
        let selectedColor: Color
        let unselectedColor: Color
        let iconSize: CGFloat
        let labelFont: Font
        let innerSpacing: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat

        static let standard = Style(
            selectedColor: ColorTokens.standard.ink,
            unselectedColor: ColorTokens.standard.ink3,
            iconSize: 25,
            labelFont: TypographyTokens.standard.monoSmall,
            innerSpacing: SpacingScale.standard.xs,
            verticalPadding: SpacingScale.standard.xs,
            horizontalPadding: SpacingScale.standard.sm
        )
    }

    struct Tab {
        let icon: String
        let label: String

        init(icon: String, label: String) {
            self.icon = icon
            self.label = label
        }
    }
}
