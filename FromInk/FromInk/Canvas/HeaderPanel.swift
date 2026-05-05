import SwiftUI

struct HeaderPanel: View {
    let headers: [CanvasHeader]
    /// True when the toolbar is on the left — determines which edge gets the border and shadow.
    let toolbarOnLeft: Bool
    let onNavigate: (CanvasHeader) -> Void
    let onDismiss: () -> Void

    private var sorted: [CanvasHeader] {
        headers.sorted { $0.contentRect.minY < $1.contentRect.minY }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Headers")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.border.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.border)
                .frame(height: 1)

            if sorted.isEmpty {
                Spacer()
                Text("No headers yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary.opacity(0.5))
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sorted) { header in
                            HeaderCell(header: header) {
                                onNavigate(header)
                            }
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .frame(width: 420)
        .frame(maxHeight: .infinity)
        .background(Color.surface)
        // Inner-edge border
        .overlay(alignment: toolbarOnLeft ? .leading : .trailing) {
            Rectangle()
                .fill(Color.border)
                .frame(width: 1)
        }
        // Shadow cast toward the canvas
        .shadow(
            color: .black.opacity(0.14),
            radius: 20,
            x: toolbarOnLeft ? -8 : 8,
            y: 0
        )
    }
}
