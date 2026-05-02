import SwiftUI

struct TemplatePickerPanel: View {
    @Binding var template: CanvasTemplate
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.border).frame(height: 1)
            ForEach(CanvasTemplate.allCases, id: \.self) { option in
                templateRow(option)
            }
        }
        .frame(width: 220)
        .background(Color.surface)
        .overlay(Rectangle().strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Template")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Row

    private func templateRow(_ option: CanvasTemplate) -> some View {
        let isSelected = template == option
        return Button {
            withAnimation(.linear(duration: 0.08)) {
                template = option
            }
        } label: {
            HStack(spacing: 12) {
                thumbnail(option, selected: isSelected)
                Text(option.displayName)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.inkOnDark : Color.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(isSelected ? Color.ink : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail

    private func thumbnail(_ option: CanvasTemplate, selected: Bool) -> some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.canvas)
            )
            TemplateView.draw(option, in: context, size: size, spacing: option.thumbnailSpacing)
        }
        .frame(width: 36, height: 36)
        .overlay(
            Rectangle()
                .strokeBorder(selected ? Color.inkOnDark.opacity(0.4) : Color.border, lineWidth: 1)
        )
    }
}

#Preview {
    Color.canvas.ignoresSafeArea()
        .overlay {
            TemplatePickerPanel(template: .constant(.linesCollege))
        }
}
