import SwiftUI

/// A header row in the dispatch panel headers tab.
/// Shows resolved text and optional handwriting image.
/// Component view — no TCA imports.
///
struct DispatchHeaderRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: model.innerSpacing) {
                if model.showSpinner {
                    HStack(spacing: model.innerSpacing) {
                        ProgressView().scaleEffect(0.75)
                        Text(model.displayText)
                            .font(model.textFont)
                            .foregroundStyle(model.textColor)
                    }
                } else {
                    Text(model.displayText)
                        .font(model.textFont)
                        .foregroundStyle(model.textColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: model.imageMinHeight)
                        .background(model.imageBackground)
                        .overlay {
                            Rectangle()
                                .strokeBorder(
                                    model.imageBorderColor,
                                    lineWidth: model.borderWidth
                                )
                        }
                }
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(DispatchRowPressStyle())
    }
}

// MARK: - Model

extension DispatchHeaderRow {
    struct Model {
        let id: String
        let displayText: String
        let showSpinner: Bool
        let image: UIImage?
        let onTap: () -> Void
        let textFont: Font
        let textColor: Color
        let imageBackground: Color
        let imageBorderColor: Color
        let imageMinHeight: CGFloat
        let borderWidth: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let innerSpacing: CGFloat
    }
}

// MARK: - Model init

extension DispatchHeaderRow.Model {
    init(
        id: String,
        ocrText: String?,
        image: UIImage?,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.image = image
        self.onTap = onTap

        switch ocrText {
        case nil:
            self.displayText = AppStrings.Dispatch.recognizing
            self.showSpinner = true
            self.textColor = ds.colors.ink3
        case let text? where text.isEmpty:
            self.displayText = AppStrings.Dispatch.headerPlaceholder
            self.showSpinner = false
            self.textColor = ds.colors.ink3
        case let text?:
            self.displayText = text
            self.showSpinner = false
            self.textColor = ds.colors.ink2
        }

        self.textFont = ds.typography.footnote
        self.imageBackground = ds.colors.paper
        self.imageBorderColor = ds.colors.rule
        self.imageMinHeight = ds.layout.headerPreviewMinHeight
        self.borderWidth = ds.layout.borderWidth
        self.horizontalPadding = ds.spacing.base
        self.verticalPadding = ds.spacing.md
        self.innerSpacing = ds.spacing.sm
    }
}
