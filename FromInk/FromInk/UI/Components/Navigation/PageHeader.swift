import SwiftUI

/// Page-level header with display title, subtitle, and optional action.
/// Uses serif display typography for the title.
///
///     PageHeader(model: .init(
///         title: "May 07",
///         subtitle: "Wednesday",
///         action: ("New Note", createNote)
///     ))
///
struct PageHeader: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRule()

            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow = model.eyebrow {
                    MonoLabel(eyebrow, color: Color("ink/Ink3"))
                        .padding(.bottom, 4)
                }

                Text(model.title)
                    .font(.system(size: 48, weight: .light, design: .serif))
                    .foregroundStyle(Color("ink/Ink"))

                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color("ink/Ink2"))
                }

                if let action = model.action {
                    InkButton(action.label, style: .tinted, action: action.handler)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }
}

extension PageHeader {
    struct Model {
        let title: String
        let subtitle: String?
        let eyebrow: String?
        let action: (label: String, handler: () -> Void)?

        init(
            title: String,
            subtitle: String? = nil,
            eyebrow: String? = nil,
            action: (String, () -> Void)? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.eyebrow = eyebrow
            if let action {
                self.action = (action.0, action.1)
            } else {
                self.action = nil
            }
        }
    }
}
