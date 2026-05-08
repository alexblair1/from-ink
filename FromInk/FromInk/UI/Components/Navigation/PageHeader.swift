import SwiftUI

/// Page-level header with display title, subtitle, and optional action.
/// Uses serif display typography for the title.
///
///     PageHeader(model: .init(
///         title: "May 07",
///         subtitle: "Wednesday",
///         action: ("New Note", createNote)
///     ))
///
struct PageHeader: View {

    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRule()

            VStack(alignment: .leading, spacing: model.style.innerSpacing) {
                if let eyebrow = model.eyebrow {
                    MonoLabel(eyebrow, color: model.style.eyebrowColor)
                        .padding(.bottom, model.style.eyebrowSpacing)
                }

                Text(model.title)
                    .font(model.style.titleFont)
                    .foregroundStyle(model.style.titleColor)

                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(model.style.subtitleFont)
                        .foregroundStyle(model.style.subtitleColor)
                }

                if let action = model.action {
                    InkButton(action.label, style: .tinted, action: action.handler)
                        .padding(.top, SpacingScale.standard.md)
                }
            }
            .padding(.horizontal, model.style.horizontalPadding)
            .padding(.vertical, model.style.verticalPadding)
        }
    }
}

extension PageHeader {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let subtitleFont: Font
        let subtitleColor: Color
        let eyebrowColor: Color
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let eyebrowSpacing: CGFloat
        let innerSpacing: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.display(size: 48),
            titleColor: ColorTokens.standard.ink,
            subtitleFont: TypographyTokens.standard.body,
            subtitleColor: ColorTokens.standard.ink2,
            eyebrowColor: ColorTokens.standard.ink3,
            horizontalPadding: SpacingScale.standard.base,
            verticalPadding: SpacingScale.standard.lg,
            eyebrowSpacing: SpacingScale.standard.xs,
            innerSpacing: SpacingScale.standard.xs
        )
    }

    struct Model {
        let title: String
        let subtitle: String?
        let eyebrow: String?
        let action: (label: String, handler: () -> Void)?
        let style: Style

        init(
            title: String,
            subtitle: String? = nil,
            eyebrow: String? = nil,
            action: (String, () -> Void)? = nil,
            style: Style = .standard
        ) {
            self.title = title
            self.subtitle = subtitle
            self.eyebrow = eyebrow
            if let action {
                self.action = (action.0, action.1)
            } else {
                self.action = nil
            }
            self.style = style
        }
    }
}
