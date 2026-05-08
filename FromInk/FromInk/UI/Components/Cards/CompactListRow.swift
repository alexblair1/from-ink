import SwiftUI

/// Minimal single-line row with leading icon and trailing accessory.
///
///     CompactListRow(model: .init(
///         title: "Settings",
///         icon: "gearshape",
///         onTap: { }
///     ))
///
struct CompactListRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if let icon = model.icon {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color("ink/Ink2"))
                            .frame(width: 24)
                    }

                    Text(model.title)
                        .font(.body)
                        .foregroundStyle(Color("ink/Ink"))
                        .lineLimit(1)

                    Spacer()

                    if let trailingText = model.trailingText {
                        Text(trailingText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color("ink/Ink3"))
                    }

                    if model.showChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color("ink/Ink3"))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                HairlineRule()
            }
        }
        .buttonStyle(.plain)
    }
}

extension CompactListRow {
    struct Model {
        let title: String
        let icon: String?
        let trailingText: String?
        let showChevron: Bool
        let onTap: () -> Void

        init(
            title: String,
            icon: String? = nil,
            trailingText: String? = nil,
            showChevron: Bool = true,
            onTap: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.trailingText = trailingText
            self.showChevron = showChevron
            self.onTap = onTap
        }
    }
}
