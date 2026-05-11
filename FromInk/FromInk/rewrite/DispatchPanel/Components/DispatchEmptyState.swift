import SwiftUI

/// Empty state for a dispatch panel tab.
/// Uses serif font for editorial tone.
/// Component view — no TCA imports.
///
struct DispatchEmptyState: View {
    let model: Model

    var body: some View {
        VStack {
            Spacer()
            Text(model.message)
                .font(model.font)
                .foregroundStyle(model.color)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Model

extension DispatchEmptyState {
    struct Model {
        let message: String
        let font: Font
        let color: Color
    }
}

// MARK: - Model init

extension DispatchEmptyState.Model {
    init(
        message: String,
        ds: DesignSystem = .standard
    ) {
        self.message = message
        self.font = ds.typography.editorBody
        self.color = ds.colors.ink3
    }
}
