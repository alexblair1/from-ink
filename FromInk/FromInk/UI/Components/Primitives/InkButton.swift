import SwiftUI

/// Three-variant button matching the Native Kit spec.
///
///     InkButton("Save note", style: .filled, action: save)
///     InkButton("Add to Notebook", style: .tinted, action: add)
///     InkButton("Cancel", style: .ghost, action: cancel)
///     InkButton("Share", style: .filled, icon: "square.and.arrow.up", action: share)
///
struct InkButton: View {

    let title: String
    let style: Style
    let icon: String?
    let theme: Theme
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .filled,
        icon: String? = nil,
        theme: Theme = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.theme = theme
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.iconSpacing) {
                if let icon {
                    Image(systemName: icon)
                        .font(theme.font)
                        .symbolRenderingMode(.monochrome)
                }
                Text(title)
                    .font(theme.font)
            }
            .padding(.vertical, theme.verticalPadding)
            .padding(.horizontal, theme.horizontalPadding)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .overlay {
                if style != .ghost {
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .filled: theme.filledForeground
        case .tinted, .ghost: theme.ghostForeground
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .filled: theme.filledBackground
        case .tinted: theme.tintedBackground
        case .ghost: .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .filled: theme.filledBackground
        case .tinted, .ghost: .clear
        }
    }
}

// MARK: - Style

extension InkButton {
    enum Style {
        /// Ink background, paper text. Primary CTA.
        case filled
        /// Ink @ 8% background, ink text. Secondary action.
        case tinted
        /// Transparent, ink text. Nav bar leading, footers.
        case ghost
    }
}

// MARK: - Theme

extension InkButton {
    struct Theme {
        let font: Font
        let iconSpacing: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
        let cornerRadius: CGFloat
        let filledForeground: Color
        let filledBackground: Color
        let tintedForeground: Color
        let tintedBackground: Color
        let ghostForeground: Color

        static let standard = Theme(
            font: TypographyTokens.standard.subheadline,
            iconSpacing: SpacingScale.standard.sm,
            verticalPadding: 10,
            horizontalPadding: 18,
            cornerRadius: CornerRadiusScale.standard.content,
            filledForeground: ColorTokens.standard.paperOnInk,
            filledBackground: ColorTokens.standard.ink,
            tintedForeground: ColorTokens.standard.ink,
            tintedBackground: ColorTokens.standard.ink.opacity(0.08),
            ghostForeground: ColorTokens.standard.ink
        )
    }
}
