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

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let isSelected = selectedIndex == index

                    Button {
                        selectedIndex = index
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 25, weight: isSelected ? .medium : .regular))
                                .symbolRenderingMode(.monochrome)

                            Text(tab.label)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(10 * 0.18)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(isSelected ? Color("ink/Ink") : Color("ink/Ink3"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(.regularMaterial)
    }
}

extension InkTabBar {
    struct Tab {
        let icon: String
        let label: String

        init(icon: String, label: String) {
            self.icon = icon
            self.label = label
        }
    }
}
