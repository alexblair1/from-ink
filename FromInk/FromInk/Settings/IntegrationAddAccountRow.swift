import SwiftUI

/// Action row pinned at the bottom of each provider group. Tapping
/// it initiates the add-account flow for that provider — the
/// provider is implied by which group the row lives in, so there's
/// no separate "pick a provider" picker.
///
/// Component view: zero state, zero TCA.
///
struct IntegrationAddAccountRow: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: model.onTap) {
            HStack {
                Text(model.label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ds.colors.ink2)

                Spacer()
            }
            .padding(.horizontal, ds.spacing.sm)
            .frame(minHeight: ds.layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension IntegrationAddAccountRow {
    struct Model: Equatable {
        let label: String
        let onTap: () -> Void

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.label == rhs.label
        }
    }
}
