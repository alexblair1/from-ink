import SwiftUI

struct NotebookCard: View {
    let notebook: Notebook
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover accent strip
                Rectangle()
                    .fill(coverColor)
                    .frame(height: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(notebook.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Text(notebook.lastOpenedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 120)
            .background(Color.surface)
            .overlay {
                Rectangle()
                    .strokeBorder(Color.border, lineWidth: 1)
            }
        }
        .buttonStyle(CardButtonStyle())
    }

    private var coverColor: Color {
        Color(hex: notebook.coverColorHex) ?? Color.ink
    }
}

// MARK: - Color hex init

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6,
              let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Card button style

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.linear(duration: 0.08), value: configuration.isPressed)
    }
}
