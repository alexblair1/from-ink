import SwiftUI

/// Top navigation bar with leading/trailing actions and centered title.
/// Uses regular material when scrolled, transparent at rest.
///
///     InkNavBar(model: .init(
///         title: "Notebooks",
///         leadingIcon: "chevron.left",
///         onLeading: goBack,
///         trailingIcon: "plus",
///         onTrailing: addNew
///     ))
///
struct InkNavBar: View {

    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let leadingIcon = model.leadingIcon, let onLeading = model.onLeading {
                    IconButton(leadingIcon, size: .body, action: onLeading)
                } else if let leadingLabel = model.leadingLabel, let onLeading = model.onLeading {
                    Button(action: onLeading) {
                        Text(leadingLabel)
                            .font(model.style.labelFont)
                            .foregroundStyle(model.style.labelColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: model.style.hitTarget)
                }

                Spacer()

                if let title = model.title {
                    MonoLabel(title)
                }

                Spacer()

                if let trailingIcon = model.trailingIcon, let onTrailing = model.onTrailing {
                    IconButton(trailingIcon, size: .body, action: onTrailing)
                } else {
                    Spacer().frame(width: model.style.hitTarget)
                }
            }
            .padding(.horizontal, model.style.horizontalPadding)
            .frame(height: model.style.height)

            HairlineRule()
        }
    }
}

extension InkNavBar {
    struct Style {
        let labelFont: Font
        let labelColor: Color
        let height: CGFloat
        let horizontalPadding: CGFloat
        let hitTarget: CGFloat

        static let standard = Style(
            labelFont: TypographyTokens.standard.subheadline,
            labelColor: ColorTokens.standard.ink,
            height: LayoutTokens.standard.hitTarget,
            horizontalPadding: SpacingScale.standard.sm,
            hitTarget: LayoutTokens.standard.hitTarget
        )
    }

    struct Model {
        let title: String?
        let leadingIcon: String?
        let leadingLabel: String?
        let onLeading: (() -> Void)?
        let trailingIcon: String?
        let onTrailing: (() -> Void)?
        let style: Style

        init(
            title: String? = nil,
            leadingIcon: String? = nil,
            leadingLabel: String? = nil,
            onLeading: (() -> Void)? = nil,
            trailingIcon: String? = nil,
            onTrailing: (() -> Void)? = nil,
            style: Style = .standard
        ) {
            self.title = title
            self.leadingIcon = leadingIcon
            self.leadingLabel = leadingLabel
            self.onLeading = onLeading
            self.trailingIcon = trailingIcon
            self.onTrailing = onTrailing
            self.style = style
        }
    }
}
