import SwiftUI

/// Section divider with mono label, count, and optional trailing action.
///
///     SectionHeader(model: .init(title: "Notebooks", count: 3))
///     SectionHeader(model: .init(title: "Folders", count: 5, action: ("View all", viewAll)))
///
struct SectionHeader<Trailing: View>: View {

    let model: Model
    let trailing: () -> Trailing

    init(
        model: Model,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.model = model
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(alignment: .firstTextBaseline, spacing: model.style.itemSpacing) {
                MonoLabel(model.title)

                if let count = model.count {
                    MonoLabel("\u{00B7} \(count)", color: model.style.countColor)
                }

                Spacer()

                if let action = model.action {
                    Button(action: action.handler) {
                        MonoLabel("\(action.label) \u{2192}", color: model.style.actionColor)
                    }
                    .buttonStyle(.plain)
                }

                trailing()
            }
            .padding(.vertical, model.style.verticalPadding)
        }
    }
}

// MARK: - Style

struct SectionHeaderStyle {
    let itemSpacing: CGFloat
    let verticalPadding: CGFloat
    let countColor: Color
    let actionColor: Color

    static let standard = SectionHeaderStyle(
        itemSpacing: SpacingScale.standard.sm,
        verticalPadding: SpacingScale.standard.md,
        countColor: ColorTokens.standard.tertiaryLabel,
        actionColor: ColorTokens.standard.ink
    )
}

// MARK: - Model

extension SectionHeader {
    struct Model {
        let title: String
        let count: Int?
        let action: (label: String, handler: () -> Void)?
        let style: SectionHeaderStyle

        init(
            title: String,
            count: Int? = nil,
            action: (String, () -> Void)? = nil,
            style: SectionHeaderStyle = .standard
        ) {
            self.title = title
            self.count = count
            if let action {
                self.action = (action.0, action.1)
            } else {
                self.action = nil
            }
            self.style = style
        }
    }
}
