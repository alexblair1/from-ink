import SwiftUI

struct NotebookCard: View {
    let notebook: Notebook
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            NotebookCardContent(notebook: notebook)
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - Card content (reads pressed state from environment)

private struct NotebookCardContent: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "book.closed.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.primary)
                .frame(width: 150, height: 150)

            Text(notebook.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Text(notebook.lastOpenedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 10))
                .foregroundStyle(Color.inkSecondary)
        }
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

// MARK: - Pressed environment key

private struct CardPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var cardIsPressed: Bool {
        get { self[CardPressedKey.self] }
        set { self[CardPressedKey.self] = newValue }
    }
}

// MARK: - Card button style

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.cardIsPressed, configuration.isPressed)
    }
}
