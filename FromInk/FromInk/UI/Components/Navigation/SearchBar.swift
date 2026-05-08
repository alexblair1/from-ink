import SwiftUI

/// Search input field with monochrome styling and thin material when active.
///
///     SearchBar(text: $query, placeholder: "Search notebooks...")
///
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onCommit: (() -> Void)?

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "Search...",
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color("ink/Ink2"))

            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color("ink/Ink"))
                .focused($isFocused)
                .onSubmit { onCommit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color("ink/Ink3"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isFocused ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color("ink/Surface"))
        )
        .overlay(
            Rectangle()
                .strokeBorder(Color("ink/Rule"), lineWidth: 0.5)
        )
    }
}
