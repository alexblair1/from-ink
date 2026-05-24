import SwiftUI

struct HeaderIndicator: View {
    let header: NoteHeaderSnapshot

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1.5)
            }
            .frame(width: header.rect.width, height: header.rect.height)
            .overlay(alignment: .topLeading) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.surface)
                    .padding(4)
                    .background(Color.inkSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .offset(x: -4, y: -4)
            }
            .allowsHitTesting(false)
    }
}
