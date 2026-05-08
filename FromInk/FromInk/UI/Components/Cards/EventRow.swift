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
                HStack(spacing: 12) {
                    // Time block
                    VStack(alignment: .trailing, spacing: 2) {
                        MonoLabel(model.time, color: Color("ink/Ink"))
                        if let duration = model.duration {
                            MonoLabel(duration, color: Color("ink/Ink3"))
                        }
                    }
                    .frame(width: 72, alignment: .trailing)

                    // Color accent bar
                    Rectangle()
                        .fill(model.accentColor)
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color("ink/Ink"))
                            .lineLimit(1)

                        if let location = model.location {
                            Text(location)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color("ink/Ink2"))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                HairlineRule()
            }
        }
        .buttonStyle(.plain)
    }
}

extension EventRow {
    struct Model {
        let id: UUID
        let title: String
        let time: String
        let duration: String?
        let location: String?
        let accentColor: Color
        let onTap: () -> Void

        init(
            id: UUID = UUID(),
            title: String,
            time: String,
            duration: String? = nil,
            location: String? = nil,
            accentColor: Color = Color("ink/Ink"),
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.time = time
            self.duration = duration
            self.location = location
            self.accentColor = accentColor
            self.onTap = onTap
        }
    }
}
