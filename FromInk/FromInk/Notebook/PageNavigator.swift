import SwiftUI

struct PageNavigator: View {
    let current: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAddPage: () -> Void

    private var isAtLastPage: Bool { current >= total }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(current <= 1)

            Text("\(current) / \(total)")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 48)

            // At the last page the forward affordance becomes "add a new
            // page" — a bold `plus` in `inkPure` so it reads as the
            // primary action rather than another navigation chevron.
            // `.contentTransition(.symbolEffect(.replace))` morphs the
            // icon in place so it reads as a state change.
            Button(action: isAtLastPage ? onAddPage : onNext) {
                Image(systemName: isAtLastPage ? "plus" : "chevron.right")
                    .font(.system(size: 14, weight: isAtLastPage ? .bold : .regular))
                    .foregroundStyle(isAtLastPage
                        ? DesignSystem.standard.colors.inkPure
                        : Color.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .foregroundStyle(Color.inkSecondary)
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.gray.opacity(0.2).ignoresSafeArea()
        .overlay {
            PageNavigator(current: 2, total: 5, onPrevious: {}, onNext: {}, onAddPage: {})
        }
}
