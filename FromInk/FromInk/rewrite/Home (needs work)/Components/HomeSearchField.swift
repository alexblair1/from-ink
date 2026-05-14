import SwiftUI

/// Search input field on the home screen.
/// Component view — no TCA imports.
///
struct HomeSearchField: View {
    let model: Model
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: model.innerSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: model.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.iconColor)

            TextField(model.placeholder, text: $text)
                .font(model.font)
                .foregroundStyle(model.textColor)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: model.iconSize, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.clearColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, model.fieldPaddingH)
        .padding(.vertical, model.fieldPaddingV)
        .background(model.background)
        .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius))
        .padding(.horizontal, model.outerPaddingH)
        .padding(.vertical, model.outerPaddingV)
    }
}

// MARK: - Model

extension HomeSearchField {
    struct Model {
        let placeholder: String
        let font: Font
        let textColor: Color
        let iconColor: Color
        let clearColor: Color
        let background: Color
        let borderColor: Color
        let borderWidth: CGFloat
        let cornerRadius: CGFloat
        let iconSize: CGFloat
        let innerSpacing: CGFloat
        let fieldPaddingH: CGFloat
        let fieldPaddingV: CGFloat
        let outerPaddingH: CGFloat
        let outerPaddingV: CGFloat
    }
}

// MARK: - Model init

extension HomeSearchField.Model {
    init(ds: DesignSystem = .standard) {
        self.placeholder = AppStrings.Home.searchPlaceholder
        self.font = ds.typography.subheadline
        self.textColor = ds.colors.ink
        self.iconColor = ds.colors.ink3
        self.clearColor = ds.colors.ink3
        self.background = ds.colors.surface
        self.borderColor = .clear
        self.borderWidth = 0
        self.cornerRadius = ds.cornerRadius.row
        self.iconSize = ds.layout.searchIconSize
        self.innerSpacing = ds.spacing.sm
        self.fieldPaddingH = ds.spacing.base
        self.fieldPaddingV = ds.spacing.md
        self.outerPaddingH = ds.spacing.lg
        self.outerPaddingV = ds.spacing.base
    }
}
