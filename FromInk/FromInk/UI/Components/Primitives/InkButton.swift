import SwiftUI

/// Three-variant button matching the Native Kit spec.
///
///     InkButton("Save note", style: .filled, action: save)
///     InkButton("Add to Notebook", style: .tinted, action: add)
///     InkButton("Cancel", style: .ghost, action: cancel)
///     InkButton("Share", style: .filled, icon: "square.and.arrow.up", action: share)
///
struct InkButton: View {

    enum Style {
        /// Ink background, paper text. Primary CTA.
        case filled
        /// Ink @ 8% background, ink text. Secondary action.
        case tinted
        /// Transparent, ink text. Nav bar leading, footers.
        case ghost
    }

    let title: String
    let style: Style
    let icon: String?
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .filled,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .overlay {
                if style == .ghost {
                    EmptyView()
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .filled: Color("ink/Paper")
        case .tinted, .ghost: Color("ink/Ink")
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .filled: Color("ink/Ink")
        case .tinted: Color("ink/Ink").opacity(0.08)
        case .ghost: .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .filled: Color("ink/Ink")
        case .tinted: .clear
        case .ghost: .clear
        }
    }
}
