import SwiftUI

struct PageNavigator: View {
    let current: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAddPage: () -> Void

    private let ds = DesignSystem.standard

    private var isAtLastPage: Bool { current >= total }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .disabled(current <= 1)

            Text("\(current) / \(total)")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 56)

            // At the last page the forward affordance becomes "add a new
            // page" — a bold `plus` in `inkPure` so it reads as the
            // primary action rather than another navigation chevron.
            // `.contentTransition(.symbolEffect(.replace))` morphs the
            // icon in place so it reads as a state change.
            Button(action: isAtLastPage ? onAddPage : onNext) {
                Image(systemName: isAtLastPage ? "plus" : "chevron.right")
                    .font(.system(size: 17, weight: isAtLastPage ? .bold : .regular))
                    .foregroundStyle(isAtLastPage
                        ? ds.colors.inkPure
                        : ds.colors.ink2)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .foregroundStyle(ds.colors.ink2)
        .buttonStyle(.plain)
        // Canvas-matched fill so handwriting / template lines behind the
        // navigator are masked out. Same `ink/Paper` token the notebook
        // background uses, so the rectangle reads as a "cleared" area
        // of the page rather than a separate UI element. Rectangle
        // (not capsule) per CLAUDE.md: `cornerRadius: 0` globally.
        .background(ds.colors.paper)
    }
}

#Preview {
    Color.gray.opacity(0.2).ignoresSafeArea()
        .overlay {
            PageNavigator(current: 2, total: 5, onPrevious: {}, onNext: {}, onAddPage: {})
        }
}
