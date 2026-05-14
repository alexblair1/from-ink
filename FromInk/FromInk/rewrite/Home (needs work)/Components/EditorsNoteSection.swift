import SwiftUI

/// "✦ EDITOR'S NOTE" label + two-paragraph serif body.
/// Component view — no TCA imports.
///
struct EditorsNoteSection: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: model.innerSpacing) {
            HStack(spacing: model.labelIconSpacing) {
                Image(systemName: "sparkles")
                    .font(.system(size: model.labelIconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.labelColor)
                MonoLabel(model.label, color: model.labelColor)
            }

            ForEach(
                Array(model.paragraphs.enumerated()),
                id: \.offset
            ) { index, paragraph in
                Text(paragraph)
                    .font(model.bodyFont)
                    .foregroundStyle(model.bodyColor)
                    .lineSpacing(model.lineSpacing)
                    .padding(.top, index == 0 ? 0 : model.paragraphSpacing)
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.topPadding)
    }
}

// MARK: - Model

extension EditorsNoteSection {
    struct Model {
        let label: String
        let paragraphs: [String]
        let labelColor: Color
        let labelIconSize: CGFloat
        let labelIconSpacing: CGFloat
        let bodyFont: Font
        let bodyColor: Color
        let lineSpacing: CGFloat
        let paragraphSpacing: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let innerSpacing: CGFloat
    }
}

// MARK: - Model init

extension EditorsNoteSection.Model {
    init(
        paragraphs: [String],
        ds: DesignSystem = .standard
    ) {
        self.label = AppStrings.Home.editorsNote
        self.paragraphs = paragraphs
        self.labelColor = ds.colors.ink2
        self.labelIconSize = ds.layout.labelIconSize
        self.labelIconSpacing = ds.spacing.xs
        self.bodyFont = ds.typography.briefLede
        self.bodyColor = ds.colors.ink
        self.lineSpacing = 6
        self.paragraphSpacing = ds.spacing.md
        self.horizontalPadding = ds.spacing.lg
        self.topPadding = ds.spacing.base
        self.innerSpacing = ds.spacing.sm
    }
}
