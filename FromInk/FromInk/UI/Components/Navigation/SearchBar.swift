import SwiftUI

/// Search input field with monochrome styling and thin material when active.
///
///     SearchBar(text: $query, placeholder: "Search notebooks...")
///
struct SearchBar: View {

    @Binding var text: String
    let placeholder: String
    let onCommit: (() -> Void)?
    let style: Style

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "Search...",
        onCommit: (() -> Void)? = nil,
        style: Style = .standard
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
        self.style = style
    }

    var body: some View {
        HStack(spacing: style.innerSpacing) {
            Image(systemName: "magnifyingglass")
                .font(style.font)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(style.iconColor)

            TextField(placeholder, text: $text)
                .font(style.font)
                .foregroundStyle(style.textColor)
                .focused($isFocused)
                .onSubmit { onCommit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(style.font)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(style.clearColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(
            isFocused ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(style.background)
        )
        .overlay(
            Rectangle()
                .strokeBorder(style.borderColor, lineWidth: 0.5)
        )
    }
}

extension SearchBar {
    struct Style {
        let font: Font
        let iconColor: Color
        let textColor: Color
        let clearColor: Color
        let background: Color
        let borderColor: Color
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let innerSpacing: CGFloat

        static let standard = Style(
            font: TypographyTokens.standard.subheadline,
            iconColor: ColorTokens.standard.ink2,
            textColor: ColorTokens.standard.ink,
            clearColor: ColorTokens.standard.ink3,
            background: ColorTokens.standard.surface,
            borderColor: ColorTokens.standard.rule,
            horizontalPadding: SpacingScale.standard.md,
            verticalPadding: SpacingScale.standard.sm,
            innerSpacing: SpacingScale.standard.sm
        )
    }
}
