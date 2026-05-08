import SwiftUI

/// Reminder row with completion toggle, title, due info, and list indicator.
///
///     ReminderRow(model: .init(
///         title: "Buy groceries",
///         dueDate: "Today, 5:00 PM",
///         isCompleted: false,
///         onToggle: { },
///         onTap: { }
///     ))
///
struct ReminderRow: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.onToggle) {
                    Image(systemName: model.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            model.isCompleted ? Color("ink/Ink3") : model.listColor
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: model.onTap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(
                                model.isCompleted ? Color("ink/Ink3") : Color("ink/Ink")
                            )
                            .strikethrough(model.isCompleted)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if let dueDate = model.dueDate {
                                MonoLabel(dueDate, color: Color("ink/Ink2"))
                            }
                            if let listName = model.listName {
                                MonoLabel("· \(listName)", color: Color("ink/Ink3"))
                            }
                        }
                    }

                    Spacer()
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            HairlineRule()
        }
    }
}

extension ReminderRow {
    struct Model {
        let id: UUID
        let title: String
        let dueDate: String?
        let listName: String?
        let listColor: Color
        let isCompleted: Bool
        let onToggle: () -> Void
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            title: String,
            dueDate: String? = nil,
            listName: String? = nil,
            listColor: Color = Color("ink/Ink"),
            isCompleted: Bool = false,
            onToggle: @escaping () -> Void,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.dueDate = dueDate
            self.listName = listName
            self.listColor = listColor
            self.isCompleted = isCompleted
            self.onToggle = onToggle
            self.onTap = onTap
        }
    }
}
