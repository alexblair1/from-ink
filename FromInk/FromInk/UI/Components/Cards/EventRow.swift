import SwiftUI

/// Calendar event row for Daily Brief and schedule views.
/// Shows time, title, location, and optional color accent.
///
///     EventRow(model: .init(
///         title: "Product Review",
///         time: "10:00 AM",
///         duration: "1h",
///         location: "Zoom",
///         onTap: { }
///     ))
///
struct EventRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(spacing: 0) {
                HStack(spacing: model.style.innerSpacing) {
                    // Time block
                    VStack(alignment: .trailing, spacing: model.style.timeSpacing) {
                        MonoLabel(model.time, color: model.style.timeColor)
                        if let duration = model.duration {
                            MonoLabel(duration, color: model.style.durationColor)
                        }
                    }
                    .frame(width: model.style.timeBlockWidth, alignment: .trailing)

                    // Color accent bar
                    Rectangle()
                        .fill(model.accentColor)
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: model.style.timeSpacing) {
                        Text(model.title)
                            .font(model.style.titleFont)
                            .foregroundStyle(model.style.titleColor)
                            .lineLimit(1)

                        if let location = model.location {
                            Text(location)
                                .font(model.style.locationFont)
                                .foregroundStyle(model.style.locationColor)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, model.style.verticalPadding)
                .padding(.horizontal, model.style.horizontalPadding)

                HairlineRule()
            }
        }
        .buttonStyle(.plain)
    }
}

extension EventRow {
    struct Style {
        let titleFont: Font
        let titleColor: Color
        let locationFont: Font
        let locationColor: Color
        let timeColor: Color
        let durationColor: Color
        let innerSpacing: CGFloat
        let timeSpacing: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
        let timeBlockWidth: CGFloat

        static let standard = Style(
            titleFont: TypographyTokens.standard.headline,
            titleColor: ColorTokens.standard.ink,
            locationFont: TypographyTokens.standard.subheadline,
            locationColor: ColorTokens.standard.ink2,
            timeColor: ColorTokens.standard.ink,
            durationColor: ColorTokens.standard.ink3,
            innerSpacing: SpacingScale.standard.md,
            timeSpacing: SpacingScale.standard.xxs,
            verticalPadding: SpacingScale.standard.md,
            horizontalPadding: SpacingScale.standard.base,
            timeBlockWidth: LayoutTokens.standard.timeBlockWidth
        )
    }

    struct Model {
        let id: UUID
        let title: String
        let time: String
        let duration: String?
        let location: String?
        let accentColor: Color
        let onTap: () -> Void
        let style: Style

        init(
            id: UUID = UUID(),
            title: String,
            time: String,
            duration: String? = nil,
            location: String? = nil,
            accentColor: Color = ColorTokens.standard.ink,
            onTap: @escaping () -> Void,
            style: Style = .standard
        ) {
            self.id = id
            self.title = title
            self.time = time
            self.duration = duration
            self.location = location
            self.accentColor = accentColor
            self.onTap = onTap
            self.style = style
        }
    }
}
