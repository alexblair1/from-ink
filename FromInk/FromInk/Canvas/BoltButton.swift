import SwiftUI

struct BoltButton: View {
    let isReady: Bool
    let action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.bolt.opacity(0.1))

                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.bolt)
                    .scaleEffect(isPulsing ? 1.24 : 1.0)
            }
            .frame(width: 48, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeIn(duration: 0.2)) { isPulsing = false }
            }
        }
    }
}
