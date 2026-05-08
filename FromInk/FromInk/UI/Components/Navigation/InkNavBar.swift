import SwiftUI

/// Top navigation bar with leading/trailing actions and centered title.
/// Uses regular material when scrolled, transparent at rest.
///
///     InkNavBar(model: .init(
///         title: "Notebooks",
///         leadingIcon: "chevron.left",
///         onLeading: goBack,
///         trailingIcon: "plus",
///         onTrailing: addNew
///     ))
///
struct InkNavBar: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let leadingIcon = model.leadingIcon, let onLeading = model.onLeading {
                    IconButton(leadingIcon, size: .body, color: Color("ink/Ink"), action: onLeading)
                } else if let leadingLabel = model.leadingLabel, let onLeading = model.onLeading {
                    Button(action: onLeading) {
                        Text(leadingLabel)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color("ink/Ink"))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 44)
                }

                Spacer()

                if let title = model.title {
                    MonoLabel(title, color: Color("ink/Ink2"))
                }

                Spacer()

                if let trailingIcon = model.trailingIcon, let onTrailing = model.onTrailing {
                    IconButton(trailingIcon, size: .body, color: Color("ink/Ink"), action: onTrailing)
                } else {
                    Spacer().frame(width: 44)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)

            HairlineRule()
        }
    }
}

extension InkNavBar {
    struct Model {
        let title: String?
        let leadingIcon: String?
        let leadingLabel: String?
        let onLeading: (() -> Void)?
        let trailingIcon: String?
        let onTrailing: (() -> Void)?

        init(
            title: String? = nil,
            leadingIcon: String? = nil,
            leadingLabel: String? = nil,
            onLeading: (() -> Void)? = nil,
            trailingIcon: String? = nil,
            onTrailing: (() -> Void)? = nil
        ) {
            self.title = title
            self.leadingIcon = leadingIcon
            self.leadingLabel = leadingLabel
            self.onLeading = onLeading
            self.trailingIcon = trailingIcon
            self.onTrailing = onTrailing
        }
    }
}
