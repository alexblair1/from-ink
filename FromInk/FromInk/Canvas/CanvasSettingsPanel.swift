import SwiftUI

struct CanvasSettingsPanel: View {
    var onDismiss: () -> Void = {}

    @AppStorage("correctHandwriting") private var correctHandwriting = true

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ds.colors.rule).frame(height: 1)
            toggleRow(
                icon: "wand.and.sparkles",
                title: "AI Handwriting Correction",
                detail: "Fix OCR errors using on-device AI",
                isOn: $correctHandwriting
            )
        }
        .fixedSize()
        .background(ds.colors.surface)
        .overlay(
            Rectangle().strokeBorder(ds.colors.rule, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ds.colors.ink2)
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(ds.colors.paper.opacity(0.5))
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
                .foregroundStyle(ds.colors.ink2)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(ds.colors.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ds.colors.ink2)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(ds.colors.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280)
    }
}
