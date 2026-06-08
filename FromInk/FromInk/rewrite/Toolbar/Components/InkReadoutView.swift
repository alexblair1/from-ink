import SwiftUI

/// Always-visible readout at the bottom of the top toolbar capsule.
/// Shows the active tool's ink color (chip) and stroke weight (pips).
///
/// Component view — no TCA imports. The active settings are resolved by
/// the toolbar adapter into a flat `Model`; this view never reads
/// `PenSettings` directly.
struct InkReadoutView: View {
    let model: Model

    var body: some View {
        VStack(spacing: model.sectionGap) {
            inkChip
            pipRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var inkChip: some View {
        Circle()
            .fill(model.inkColor)
            .frame(width: model.chipSize, height: model.chipSize)
            .padding(model.chipInnerRingWidth)
            .background(
                Circle().fill(model.chipInnerRingColor)
            )
            .padding(model.chipOuterRingWidth)
            .background(
                Circle().fill(model.chipOuterRingColor)
            )
    }

    private var pipRow: some View {
        HStack(spacing: model.pipGap) {
            ForEach(0..<model.pipCount, id: \.self) { _ in
                Circle()
                    .fill(model.pipColor)
                    .frame(width: model.pipSize, height: model.pipSize)
            }
        }
    }
}

// MARK: - Model

extension InkReadoutView {
    struct Model: Equatable {
        let inkColor: Color
        let pipColor: Color
        let pipSize: CGFloat
        let pipCount: Int
        let pipGap: CGFloat
        let chipSize: CGFloat
        let chipInnerRingColor: Color
        let chipInnerRingWidth: CGFloat
        let chipOuterRingColor: Color
        let chipOuterRingWidth: CGFloat
        let sectionGap: CGFloat
        let accessibilityLabel: String
    }
}

// MARK: - Model init

extension InkReadoutView.Model {
    /// Resolves a `PenSettings` snapshot into a readout Model.
    /// - Parameters:
    ///   - settings: The active tool's PenSettings.
    ///   - accessibilityLabel: Localized label, e.g. "Black, fine".
    ///   - ds: Design system tokens.
    init(
        settings: PenSettings,
        accessibilityLabel: String,
        ds: DesignSystem = .standard
    ) {
        // Chip color — highlighter palette vs graphite grade.
        if settings.penType.isHighlighter {
            let idx = max(0, min(PenSettings.highlighterColors.count - 1,
                                 settings.highlighterColorIndex))
            self.inkColor = PenSettings.highlighterColors[idx]
        } else {
            self.inkColor = Color(settings.grade.uiColor)
        }

        // Pip size — linear interpolation from min to max across the
        // thickness palette. thicknessIndex 0 → min, last index → max.
        let count = max(1, PenSettings.thicknesses.count)
        let normalized = CGFloat(settings.thicknessIndex) / CGFloat(count - 1)
        let range = ds.layout.inkReadoutPipMaxSize - ds.layout.inkReadoutPipMinSize
        self.pipSize = ds.layout.inkReadoutPipMinSize + range * normalized

        self.pipColor = ds.colors.ink
        self.pipCount = ds.layout.inkReadoutPipCount
        self.pipGap = ds.layout.inkReadoutPipGap
        self.chipSize = ds.layout.inkReadoutChipSize
        self.chipInnerRingColor = ds.colors.paper
        self.chipInnerRingWidth = ds.layout.inkReadoutChipInnerRingWidth
        self.chipOuterRingColor = ds.colors.rule
        self.chipOuterRingWidth = ds.layout.inkReadoutChipOuterRingWidth
        self.sectionGap = ds.layout.inkReadoutSectionGap
        self.accessibilityLabel = accessibilityLabel
    }
}
