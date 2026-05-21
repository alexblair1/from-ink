import SwiftUI

/// Black-filled header bar above each settings group ("THE EDITOR",
/// "YOUR DATA", etc.). Mono uppercase label on paper-on-ink color,
/// matching the design's editorial group-divider rhythm.
///
/// Component view: zero state, zero TCA.
///
struct SettingsGroupHeader: View {
    let title: String

    private let ds = DesignSystem.standard

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(ds.colors.paperOnInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ds.spacing.base)
            .frame(height: ds.spacing.xl)
            .background(ds.colors.ink)
    }
}
