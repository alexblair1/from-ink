import SwiftUI

/// Rich editorial row with title, excerpt, timestamp, and optional thumbnail.
/// Used for notebook entries, search results, and content previews.
///
///     EditorialRow(model: .init(
///         title: "Weekly Retro",
///         excerpt: "Discussed sprint velocity and upcoming milestones...",
///         timestamp: "May 05",
///         onTap: { }
///     ))
///
struct EditorialRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color("ink/Ink"))
                            .lineLimit(2)

                        if let excerpt = model.excerpt {
                            Text(excerpt)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color("ink/Ink2"))
                                .lineLimit(3)
                        }

                        HStack(spacing: 8) {
                            if let timestamp = model.timestamp {
                                MonoLabel(timestamp, color: Color("ink/Ink3"))
                            }
                            if let tag = model.tag {
                                MonoLabel("· \(tag)", color: Color("ink/Ink3"))
                            }
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 0)

                    if let thumbnail = model.thumbnail {
                        thumbnail
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipped()
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

extension EditorialRow {
    struct Model {
        let id: UUID
        let title: String
        let excerpt: String?
        let timestamp: String?
        let tag: String?
        let thumbnail: Image?
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            title: String,
            excerpt: String? = nil,
            timestamp: String? = nil,
            tag: String? = nil,
            thumbnail: Image? = nil,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.excerpt = excerpt
            self.timestamp = timestamp
            self.tag = tag
            self.thumbnail = thumbnail
            self.onTap = onTap
        }
    }
}
