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
                            .foregroundStyle(isSelected ? Color("ink/Paper") : Color("ink/Ink2"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(isSelected ? Color("ink/Ink") : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < tabs.count - 1 {
                        HairlineRule(.vertical)
                    }
                }
            }
            .frame(height: 44)

            HairlineRule()
        }
    }
}
