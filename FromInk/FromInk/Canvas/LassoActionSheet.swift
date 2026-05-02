import SwiftUI

struct LassoActionSheet: View {
    let recognizedText: String
    var isLoading: Bool = false
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("Create from ink")
                    .font(.canvasTitle)
                    .foregroundStyle(Color.ink)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)

            Rectangle().fill(Color.border).frame(height: 1)

            // Recognized text
            VStack(alignment: .leading, spacing: 6) {
                Text("Recognized")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reading ink…")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.inkSecondary)
                    }
                } else {
                    Text(recognizedText.isEmpty ? "No text recognized" : recognizedText)
                        .font(.system(size: 15))
                        .foregroundStyle(recognizedText.isEmpty ? Color.inkSecondary : Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Rectangle().fill(Color.border).frame(height: 1)

            // Actions
            actionRow(icon: "checklist",
                      label: "Linear Issue",
                      subtitle: "Add to your workspace") { }
            actionRow(icon: "chevron.left.forwardslash.chevron.right",
                      label: "GitHub Issue",
                      subtitle: "Open in repository") { }
            actionRow(icon: "bell",
                      label: "Reminder",
                      subtitle: "Apple Reminders") { }
            actionRow(icon: "calendar",
                      label: "Calendar Event",
                      subtitle: "Apple Calendar") { }
            actionRow(icon: "envelope",
                      label: "Mail",
                      subtitle: "Compose email") { }

            Spacer()
        }
        .background(Color.surface)
        .presentationBackground(Color.surface)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        label: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ink)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Rectangle().fill(Color.border).frame(height: 1)
    }
}

#Preview {
    Color.canvas.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            LassoActionSheet(recognizedText: "Call John about the Q3 report by Friday")
        }
}
