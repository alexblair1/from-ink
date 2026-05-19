import SwiftUI

/// Two-paragraph serif body of the editorial brief.
///
/// Originally rendered an "EDITOR'S NOTE" mono label + sparkles icon
/// above the body. Both were dropped — the prominent placement and
/// serif treatment make the editorial context obvious, and the marker
/// was taking valuable vertical space.
///
/// Component view — no TCA imports.
///
struct EditorsNoteSection: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: model.innerSpacing) {
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
        let paragraphs: [String]
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
        self.paragraphs = paragraphs
        self.bodyFont = ds.typography.briefLede
        self.bodyColor = ds.colors.ink
        self.lineSpacing = 6
        self.paragraphSpacing = ds.spacing.md
        self.horizontalPadding = ds.spacing.lg
        self.topPadding = ds.spacing.base
        self.innerSpacing = ds.spacing.sm
    }
}
