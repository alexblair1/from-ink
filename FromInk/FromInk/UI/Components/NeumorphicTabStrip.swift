import SwiftUI

/// A reusable horizontal tab strip with the neumorphic "stamped paper"
/// state model — inactive tabs raised, active tab pressed.
///
/// Knows nothing about Calendar/Reminders/Birthdays or any other domain.
/// Pass an array of `Tab` values keyed by your own `TabID` type and a
/// tap callback; the strip handles layout, neumorphic shadows, and the
/// seam-killer paper strip that masks the boundary between an active
/// tab and the panel below.
///
/// All geometry (padding, font sizes, seam dimensions) comes from
/// `DesignSystem.neumorphicTab`. Tuning the look of every strip in the
/// app happens in one place (`NeumorphicTokens.swift`); no magic numbers
/// live here.
///
/// Scales to any number of tabs — the HStack distributes available width
/// equally via `frame(maxWidth: .infinity)`. Pass `showsLabel: false` for
/// icon+count-only compact presentations (e.g. iPhone).
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
        let style = ds.neumorphicTab
        return Button(action: { onTabTapped(tab.id) }) {
            HStack(spacing: style.contentGap) {
                Image(systemName: tab.iconName)
                    .font(.system(size: style.iconSize, weight: .regular))
                    .foregroundStyle(ds.colors.ink)

                if showsLabel {
                    Text(tab.label)
                        .font(.system(size: style.labelFontSize, weight: .medium, design: .monospaced))
                        .tracking(style.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(ds.colors.ink2)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(tab.countText)
                    .font(.system(size: style.countFontSize, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(tab.isCountZero ? ds.colors.ink3 : ds.colors.ink)
            }
            .padding(.horizontal, style.tabPaddingHorizontal)
            .padding(.vertical, style.tabPaddingVertical)
            .frame(maxWidth: .infinity)
            .background(ds.colors.paper)
            .modifier(NeumorphicStateModifier(isActive: tab.isActive, elevation: ds.neumorphicElevation))
            .overlay(alignment: .bottom) {
                if tab.isActive {
                    Rectangle()
                        .fill(ds.colors.paper)
                        .frame(height: style.seamHeight)
                        .padding(.horizontal, style.seamHorizontalInset)
                        .offset(y: style.seamOffset)
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
    let elevation: NeumorphicElevation

    func body(content: Content) -> some View {
        if isActive {
            content.neumorphicPressed(elevation: elevation)
        } else {
            content.neumorphicRaised(elevation: elevation)
        }
    }
}
