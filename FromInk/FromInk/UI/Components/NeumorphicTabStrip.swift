import SwiftUI

/// A reusable horizontal tab strip with the neumorphic "stamped paper"
/// state model — inactive tabs raised, active tab pressed.
///
/// Knows nothing about Calendar/Reminders/Birthdays or any other domain.
/// Pass an array of `Tab` values keyed by your own `TabID` type and
/// configuration closures; the strip handles layout, shadows, and the
/// seam-killer paper strip that masks the boundary between an active
/// tab and the panel below.
///
/// Scales to any number of tabs — the grid distributes available width
/// equally. Pass `showsLabel: false` for icon+count-only compact
/// presentations (e.g. iPhone).
///
/// Usage:
///
/// ```swift
/// NeumorphicTabStrip(
///     tabs: [
///         .init(id: .calendar, iconName: "calendar", label: "Calendar",
///               countText: "4", isActive: activeTab == .calendar,
///               isCountZero: false),
///         // ...
///     ],
///     showsLabel: true,
///     onTabTapped: { tabID in store.send(.tabTapped(tabID)) }
/// )
/// ```
///
struct NeumorphicTabStrip<TabID: Hashable>: View {
    let tabs: [Tab]
    let showsLabel: Bool
    let onTabTapped: (TabID) -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button(action: { onTabTapped(tab.id) }) {
            HStack(spacing: 10) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.ink)

                if showsLabel {
                    Text(tab.label)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .tracking(2.3)
                        .textCase(.uppercase)
                        .foregroundStyle(ds.colors.ink2)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(tab.countText)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(tab.isCountZero ? ds.colors.ink3 : ds.colors.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(ds.colors.paper)
            .modifier(NeumorphicStateModifier(isActive: tab.isActive))
            // Seam killer — extend a paper strip down past the active
            // tab's bottom edge so the active tab's surface bleeds into
            // the panel below, hiding any subpixel boundary. Inset 4pt
            // from each side so the surrounding L+R pressed shadows are
            // not obscured.
            .overlay(alignment: .bottom) {
                if tab.isActive {
                    Rectangle()
                        .fill(ds.colors.paper)
                        .frame(height: 5)
                        .padding(.horizontal, 4)
                        .offset(y: 3)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .zIndex(tab.isActive ? 2 : 0)
        .accessibilityLabel(tab.label)
        .accessibilityValue(tab.countText)
        .accessibilityAddTraits(tab.isActive ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Tab

extension NeumorphicTabStrip {
    struct Tab: Identifiable {
        let id: TabID
        let iconName: String
        /// User-facing localized label. Hidden when the strip's `showsLabel`
        /// is false, but still spoken by VoiceOver.
        let label: String
        /// Pre-formatted count string ("4", "0", "12"). Pre-format because
        /// the strip is locale-agnostic — let callers decide.
        let countText: String
        let isActive: Bool
        /// True if the count is semantically zero; the count renders in
        /// ink-3 (quiet) instead of ink (full). Pre-computed by the
        /// adapter so the strip doesn't need to know how to count.
        let isCountZero: Bool
    }
}

// MARK: - State modifier

/// Helper that picks the right neumorphic surface treatment based on the
/// tab's active state. Wraps the `.neumorphicRaised()` / `.neumorphicPressed()`
/// extensions so they compose cleanly inside `tabButton(_:)`.
private struct NeumorphicStateModifier: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive {
            content.neumorphicPressed()
        } else {
            content.neumorphicRaised()
        }
    }
}
