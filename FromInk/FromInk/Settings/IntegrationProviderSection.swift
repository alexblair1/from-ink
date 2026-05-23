import SwiftUI

/// A single provider's group inside the Integrations list — header,
/// account rows, any in-flight pending rows, and the "+ Add account"
/// action at the bottom. Matches the Add-Account-Flow design's
/// in-list state machine: pending and error states render as row
/// mutations, not modals.
///
/// Component view: zero state, zero TCA.
///
struct IntegrationProviderSection: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            SettingsGroupHeader(title: model.headerTitle)

            VStack(spacing: 0) {
                ForEach(model.accounts) { account in
                    IntegrationAccountRow(model: account)
                    if account.id != model.accounts.last?.id || !model.pendingRows.isEmpty {
                        HairlineRule()
                    }
                }

                ForEach(model.pendingRows) { pending in
                    IntegrationPendingRow(model: pending)
                    HairlineRule()
                }

                IntegrationAddAccountRow(model: model.addAccountRow)
            }
            // Bottom rule sits flush against the next group's header,
            // matching the design's ink-bordered list strip below
            // each group.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Model

extension IntegrationProviderSection {
    struct Model: Identifiable, Equatable {
        /// Stable per provider so SwiftUI keeps section identity
        /// across reorderings or header-title changes (e.g., the
        /// "Linear · Adding" suffix mutation).
        let id: OAuthProvider
        let headerTitle: String
        let accounts: [IntegrationAccountRow.Model]
        let pendingRows: [IntegrationPendingRow.Model]
        let addAccountRow: IntegrationAddAccountRow.Model
    }
}
