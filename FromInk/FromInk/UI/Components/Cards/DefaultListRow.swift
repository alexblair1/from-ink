import SwiftUI

/// Standard two-line list row with leading icon, title, subtitle, and trailing accessory.
///
///     DefaultListRow(model: .init(
///         title: "Product Sync",
///         subtitle: "Last edited 2h ago",
///         icon: "doc.text",
///         onTap: { }
///     ))
///
struct DefaultListRow: View {
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color("ink/Ink"))
                            .lineLimit(1)

                        if let subtitle = model.subtitle {
                            Text(subtitle)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color("ink/Ink2"))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let metadata = model.metadata {
                        MonoLabel(metadata, color: Color("ink/Ink3"))
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

extension DefaultListRow {
    struct Model {
        let id: UUID
        let title: String
        let subtitle: String?
        let icon: String?
        let metadata: String?
        let showChevron: Bool
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            title: String,
            subtitle: String? = nil,
            icon: String? = nil,
            metadata: String? = nil,
            showChevron: Bool = true,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.metadata = metadata
            self.showChevron = showChevron
            self.onTap = onTap
        }
    }
}
