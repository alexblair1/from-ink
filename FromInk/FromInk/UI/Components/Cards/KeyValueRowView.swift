import SwiftUI

/// Horizontal key-value pair for metadata display. Key on the left, value on the right.
///
///     KeyValueRowView(model: .init(
///         key: AppStrings.Library.author,
///         value: "Alex Blair"
///     ))
///
struct KeyValueRowView: View {
    let model: Model

    var body: some View {
        HStack(alignment: .center, spacing: model.style.spacing) {
            Text(model.key)
                .font(model.style.font)
                .fontWeight(.light)
                .foregroundStyle(model.style.keyColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.key)

            Text(model.value)
                .font(model.style.font)
                .fontWeight(.light)
                .foregroundStyle(model.style.valueColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension KeyValueRowView {
    struct Style {
        let font: Font
        let keyColor: Color
        let valueColor: Color
        let spacing: CGFloat

        static let standard = Style(
            font: TypographyTokens.standard.caption,
            keyColor: ColorTokens.standard.secondaryLabel,
            valueColor: ColorTokens.standard.primaryLabel,
            spacing: SpacingScale.standard.md
        )
    }

    struct Model {
        let key: String
        let value: String
        let style: Style

        init(
            key: String,
            value: String,
            style: Style = .standard
        ) {
            self.key = key
            self.value = value
            self.style = style
        }
    }
}
