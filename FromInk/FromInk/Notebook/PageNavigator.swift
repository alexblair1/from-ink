import SwiftUI

struct PageNavigator: View {
    let current: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

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

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(current >= total)
        }
        .foregroundStyle(Color.inkSecondary)
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.gray.opacity(0.2).ignoresSafeArea()
        .overlay {
            PageNavigator(current: 2, total: 5, onPrevious: {}, onNext: {})
        }
}
