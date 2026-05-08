import SwiftUI

/// Segmented tab bar for panel navigation. Uses icon-only tabs with ink highlight.
///
///     PanelTabBar(
///         tabs: [("bookmark.fill", "Headers"), ("link", "Links")],
///         selectedIndex: $selected
///     )
///
struct PanelTabBar: View {

    let tabs: [(icon: String, label: String)]
    @Binding var selectedIndex: Int
    let style: Style

    init(
        tabs: [(icon: String, label: String)],
        selectedIndex: Binding<Int>,
        style: Style = .standard
    ) {
        self.tabs = tabs
        self._selectedIndex = selectedIndex
        self.style = style
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let isSelected = selectedIndex == index

                    Button {
                        selectedIndex = index
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: isSelected ? .medium : .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(isSelected ? style.selectedForeground : style.unselectedForeground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(isSelected ? style.selectedBackground : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < tabs.count - 1 {
                        HairlineRule(.vertical)
                    }
                }
            }
            .frame(height: style.height)

            HairlineRule()
        }
    }
}

extension PanelTabBar {
    struct Style {
        let selectedForeground: Color
        let unselectedForeground: Color
        let selectedBackground: Color
        let height: CGFloat
        let font: Font

        static let standard = Style(
            selectedForeground: ColorTokens.standard.paper,
            unselectedForeground: ColorTokens.standard.ink2,
            selectedBackground: ColorTokens.standard.ink,
            height: LayoutTokens.standard.hitTarget,
            font: .system(size: 15)
        )
    }
}
