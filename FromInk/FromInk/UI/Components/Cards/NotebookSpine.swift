import SwiftUI

/// Vertical notebook spine for grid layouts. Shows cover color, title, and page count.
///
///     NotebookSpine(model: .init(
///         title: "Meeting Notes",
///         pageCount: 24,
///         coverColor: Color("ink/Ink"),
///         onTap: { }
///     ))
///
struct NotebookSpine: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Spine accent strip
                Rectangle()
                    .fill(model.coverColor)
                    .frame(height: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color("ink/Ink"))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    MonoLabel("\(model.pageCount) pages", color: Color("ink/Ink3"))
                }
                .padding(12)

                HairlineRule()
            }
            .frame(minHeight: 140)
            .background(Color("ink/Surface"))
        }
        .buttonStyle(.plain)
    }
}

extension NotebookSpine {
    struct Model {
        let id: UUID
        let title: String
        let pageCount: Int
        let coverColor: Color
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            title: String,
            pageCount: Int = 0,
            coverColor: Color = Color("ink/Ink"),
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.pageCount = pageCount
            self.coverColor = coverColor
            self.onTap = onTap
        }
    }
}
