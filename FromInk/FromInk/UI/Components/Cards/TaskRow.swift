import SwiftUI

/// Dispatch task row with checkbox, title, destination badge, and optional metadata.
///
///     TaskRow(model: .init(
///         title: "Update PRD by Friday",
///         destination: "linear",
///         isCompleted: false,
///         onToggle: { },
///         onTap: { }
///     ))
///
struct TaskRow: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.onToggle) {
                    Image(systemName: model.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            model.isCompleted ? Color("ink/Ink3") : Color("ink/Ink")
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
                            if let destination = model.destination {
                                MonoLabel(destination, color: Color("ink/Ink2"))
                            }
                            if let assignee = model.assignee {
                                MonoLabel("· \(assignee)", color: Color("ink/Ink3"))
                            }
                            if let deadline = model.deadline {
                                MonoLabel("· \(deadline)", color: Color("ink/Ink3"))
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

extension TaskRow {
    struct Model {
        let id: UUID
        let title: String
        let destination: String?
        let assignee: String?
        let deadline: String?
        let isCompleted: Bool
        let onToggle: () -> Void
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            title: String,
            destination: String? = nil,
            assignee: String? = nil,
            deadline: String? = nil,
            isCompleted: Bool = false,
            onToggle: @escaping () -> Void,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.destination = destination
            self.assignee = assignee
            self.deadline = deadline
            self.isCompleted = isCompleted
            self.onToggle = onToggle
            self.onTap = onTap
        }
    }
}
