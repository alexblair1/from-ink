import SwiftUI

struct PenCustomizationPanel: View {
    let tool: CanvasTool
    @Binding var settings: PenSettings
    var onDismiss: () -> Void = {}

    private var showsHighlighterColors: Bool { settings.penType.isHighlighter }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.border).frame(height: 1)

            penTypeList
            Rectangle().fill(Color.border).frame(height: 1)

            thicknessSection
            Rectangle().fill(Color.border).frame(height: 1)

            if showsHighlighterColors {
                highlighterColorSection
            } else {
                graphiteSection
            }
        }
        .frame(width: 260)
        .background(Color.surface)
        .overlay(Rectangle().strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(tool.rawValue.capitalized)
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

    // MARK: - Pen Type List

    private var penTypeList: some View {
        VStack(spacing: 0) {
            ForEach(PenSettings.PenType.allCases, id: \.self) { type in
                penTypeRow(type)
            }
        }
    }

    private func penTypeRow(_ type: PenSettings.PenType) -> some View {
        let isSelected = settings.penType == type
        return Button {
            withAnimation(.linear(duration: 0.08)) {
                settings.penType = type
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.inkOnDark : Color.ink)
                    .frame(width: 18)
                Text(type.displayName)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.inkOnDark : Color.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(isSelected ? Color.ink : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thickness

    private var thicknessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thickness")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)

            HStack(spacing: 6) {
                ForEach(PenSettings.thicknesses.indices, id: \.self) { i in
                    thicknessBox(index: i)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func thicknessBox(index: Int) -> some View {
        let isSelected = settings.thicknessIndex == index
        let lineH = min(CGFloat(index + 1) * 1.5, 8)
        return Button {
            withAnimation(.linear(duration: 0.08)) {
                settings.thicknessIndex = index
            }
        } label: {
            ZStack {
                Rectangle()
                    .fill(isSelected ? Color.ink : Color.clear)
                Rectangle()
                    .strokeBorder(isSelected ? Color.ink : Color.border, lineWidth: 1)
                Rectangle()
                    .fill(isSelected ? Color.inkOnDark : Color.ink)
                    .frame(height: lineH)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Graphite

    private var graphiteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Graphite")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Text(settings.grade.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
            }

            gradeSlider

            HStack(spacing: 0) {
                ForEach(PenSettings.GraphiteGrade.allCases, id: \.self) { grade in
                    Text(grade.label)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.inkSecondary)
                    if grade != .nineB { Spacer() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var gradeSlider: some View {
        GeometryReader { geo in
            let grades = PenSettings.GraphiteGrade.allCases
            let count = CGFloat(grades.count - 1)
            let thumbW: CGFloat = 18
            let trackW = geo.size.width
            let step = trackW / count
            let thumbX = step * CGFloat(settings.grade.rawValue) - thumbW / 2

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [Color(white: 0.82), Color.black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 24)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: thumbW, height: 24)
                    .offset(x: max(0, min(trackW - thumbW, thumbX)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.x / trackW
                        let index = Int((fraction * count).rounded())
                        let clamped = max(0, min(grades.count - 1, index))
                        if let grade = PenSettings.GraphiteGrade(rawValue: clamped) {
                            settings.grade = grade
                        }
                    }
            )
        }
        .frame(height: 24)
    }

    // MARK: - Highlighter Color

    private var highlighterColorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)

            HStack(spacing: 10) {
                ForEach(PenSettings.highlighterColors.indices, id: \.self) { i in
                    let isSelected = settings.highlighterColorIndex == i
                    Circle()
                        .fill(PenSettings.highlighterColors[i])
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.ink, lineWidth: isSelected ? 2 : 0)
                                .padding(-3)
                        )
                        .onTapGesture {
                            withAnimation(.linear(duration: 0.08)) {
                                settings.highlighterColorIndex = i
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    Color.canvas.ignoresSafeArea()
        .overlay {
            PenCustomizationPanel(tool: .pen, settings: .constant(.default))
        }
}
