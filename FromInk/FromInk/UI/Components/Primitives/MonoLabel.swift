import SwiftUI

/// SF Mono Medium 11pt, +18% tracking, uppercase.
/// Used for eyebrows, runners, timestamps, sync status, sheet titles.
///
///     MonoLabel("Daily brief · synced 2m ago")
///     MonoLabel("3 notebooks", color: Color("ink/Ink2"))
///     MonoLabel("May 07, 2026", size: 10)
///
struct MonoLabel: View {
    let text: String
    let size: CGFloat
    let color: Color

    init(_ text: String, size: CGFloat = 11, color: Color = Color("ink/Ink2")) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(size * 0.18)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
