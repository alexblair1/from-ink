import SwiftUI

/// A link row in the dispatch panel links tab.
/// Component view — no TCA imports.
///
struct DispatchLinkRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: model.innerSpacing) {
                Image(systemName: "link")
                    .font(model.iconFont)
                    .foregroundStyle(model.secondaryColor)
                    .frame(width: model.iconFrame)

                VStack(alignment: .leading, spacing: model.textSpacing) {
                    if !model.recognizedText.isEmpty {
                        Text(model.recognizedText)
                            .font(model.titleFont)
                            .foregroundStyle(model.titleColor)
                            .lineLimit(1)
                    }
                    Text(model.urlDisplay)
                        .font(model.urlFont)
                        .foregroundStyle(model.secondaryColor)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(model.urlFont)
                    .foregroundStyle(model.secondaryColor)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(DispatchRowPressStyle())
    }
}

// MARK: - Model

extension DispatchLinkRow {
    struct Model {
        let id: String
        let recognizedText: String
        let urlDisplay: String
        let onTap: () -> Void
        let iconFont: Font
        let titleFont: Font
        let urlFont: Font
        let titleColor: Color
        let secondaryColor: Color
        let iconFrame: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let innerSpacing: CGFloat
        let textSpacing: CGFloat
    }
}

// MARK: - Model init

extension DispatchLinkRow.Model {
    init(
        id: String,
        recognizedText: String,
        url: URL,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.recognizedText = recognizedText
        self.urlDisplay = url.host() ?? url.absoluteString
        self.onTap = onTap
        self.iconFont = ds.typography.footnote
        self.titleFont = ds.typography.subheadline
        self.urlFont = ds.typography.caption
        self.titleColor = ds.colors.ink
        self.secondaryColor = ds.colors.ink2
        self.iconFrame = ds.layout.iconFrame
        self.horizontalPadding = ds.spacing.base
        self.verticalPadding = ds.spacing.md
        self.innerSpacing = ds.spacing.sm
        self.textSpacing = ds.spacing.xxs
    }
}
