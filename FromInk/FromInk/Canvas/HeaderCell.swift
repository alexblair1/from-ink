import SwiftUI

struct HeaderCell: View {
    let header: CanvasHeader
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // OCR text — top of cell
                if let text = header.ocrText {
                    Text(text.isEmpty ? "—" : text)
                        .font(.system(size: 13))
                        .foregroundStyle(text.isEmpty ? Color.inkSecondary.opacity(0.4) : Color.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.75)
                        Text("Recognizing…")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkSecondary.opacity(0.6))
                    }
                }

                // Handwriting image — full width, larger
                Image(uiImage: header.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 80)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.border, lineWidth: 1)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
