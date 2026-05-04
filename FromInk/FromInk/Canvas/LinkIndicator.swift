import SwiftUI

struct LinkIndicator: View {
    let link: CanvasLink
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dashed selection border around the linked region
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: link.contentRect.width, height: link.contentRect.height)

            // Link badge — tappable, opens URL
            Button(action: onTap) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.surface)
                    .padding(4)
                    .background(Color.inkSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .allowsHitTesting(true)
    }
}
