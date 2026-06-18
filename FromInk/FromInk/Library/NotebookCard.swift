import SwiftUI

struct NotebookCard: View {
    let notebook: Notebook
    let onTap: () -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Portrait card with drawn notebook illustration
                ZStack {
                    ds.colors.surface
                    notebookIllustration
                }
                .frame(width: 130, height: 160)
                .overlay {
                    Rectangle().strokeBorder(ds.colors.rule, lineWidth: 1)
                }

                Text(notebook.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ds.colors.ink)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)

                Text(notebook.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(ds.colors.ink2)
                    .frame(width: 130, alignment: .leading)
            }
        }
        .buttonStyle(CardButtonStyle())
    }

    // Drawn notebook: spine strip on left, page body to the right
    private var notebookIllustration: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(ds.colors.ink)
                .frame(width: 10)
            ds.colors.paper
        }
        .frame(width: 72, height: 100)
        .overlay {
            Rectangle().strokeBorder(ds.colors.ink, lineWidth: 1.5)
        }
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
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.linear(duration: 0.08), value: configuration.isPressed)
    }
}
