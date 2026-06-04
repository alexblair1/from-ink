import SwiftUI

/// Branded overlay (scrim + centered card) for the event action sheet.
/// Single layout, two action lists driven by `Model.actions` resolved
/// upstream from the linked / unlinked state. View carries no logic —
/// it's a presentation shell.
///
/// Component view: zero TCA imports. Tap handlers are baked into the
/// action rows by the home wiring view's adapter.
///
struct EventActionSheetView: View {
    let model: Model

    var body: some View {
        ZStack {
            model.scrimColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: model.onScrimTap)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                header
                HairlineRule()

                VStack(alignment: .leading, spacing: 0) {
                    if let subtitle = model.subtitle {
                        Text(subtitle)
                            .font(model.subtitleFont)
                            .foregroundStyle(model.subtitleColor)
                            .padding(.horizontal, model.subtitleHorizontalPadding)
                            .padding(.vertical, model.subtitleVerticalPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HairlineRule()
                    }

                    ForEach(Array(model.actions.enumerated()), id: \.offset) { offset, row in
                        EventActionSheetActionRow(model: row)
                        if offset < model.actions.count - 1 {
                            HairlineRule()
                        }
                    }
                }
            }
            .frame(width: model.cardWidth)
            .background(model.cardBackground)
            .overlay(
                Rectangle().strokeBorder(model.cardBorderColor, lineWidth: model.cardBorderWidth)
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text(model.title)
                .font(model.titleFont)
                .foregroundStyle(model.titleColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: model.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: model.dismissIconSize, weight: .regular))
                    .foregroundStyle(model.dismissIconColor)
                    .frame(width: model.dismissFrame, height: model.dismissFrame)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.dismissAccessibilityLabel)
        }
        .padding(.horizontal, model.headerHorizontalPadding)
        .frame(height: model.headerHeight)
    }
}

// MARK: - Model

extension EventActionSheetView {
    struct Model: Equatable {
        let title: String
        /// Recurring-event scope line ("This notebook will cover all
        /// instances..."). Nil when the event is one-shot.
        let subtitle: String?
        let actions: [EventActionSheetActionRow.Model]
        let onDismiss: () -> Void
        let onScrimTap: () -> Void
        let dismissAccessibilityLabel: String

        let cardWidth: CGFloat
        let cardBackground: Color
        let cardBorderColor: Color
        let cardBorderWidth: CGFloat
        let scrimColor: Color

        let titleFont: Font
        let titleColor: Color
        let subtitleFont: Font
        let subtitleColor: Color
        let subtitleHorizontalPadding: CGFloat
        let subtitleVerticalPadding: CGFloat

        let headerHorizontalPadding: CGFloat
        let headerHeight: CGFloat
        let dismissIconSize: CGFloat
        let dismissFrame: CGFloat
        let dismissIconColor: Color

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.title == rhs.title
                && lhs.subtitle == rhs.subtitle
                && lhs.actions == rhs.actions
                && lhs.cardWidth == rhs.cardWidth
        }
    }
}
