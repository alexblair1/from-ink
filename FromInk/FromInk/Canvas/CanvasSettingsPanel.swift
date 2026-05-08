import SwiftUI

struct CanvasSettingsPanel: View {
    var onDismiss: () -> Void = {}

    @AppStorage("correctHandwriting") private var correctHandwriting = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.border).frame(height: 1)
            toggleRow(
                icon: "wand.and.sparkles",
                title: "AI Handwriting Correction",
                detail: "Fix OCR errors using on-device AI",
                isOn: $correctHandwriting
            )
        }
        .fixedSize()
        .background(Color.surface)
        .overlay(
            Rectangle().strokeBorder(Color.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.canvas.opacity(0.5))
    }

    private func toggleRow(
        icon: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280)
    }
}
