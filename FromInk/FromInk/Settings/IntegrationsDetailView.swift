import SwiftUI

/// Integrations detail — V1 stub. Empty-state shape ready for the
/// PKCE-authenticated integrations list per `pkce_edd.md` and
/// `integration_matrix_edd.md`.
///
/// Component view: zero state, zero TCA. Header chrome shared with
/// the option-picker detail screens via `SettingsDetailHeader`.
///
struct IntegrationsDetailView: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsDetailHeader(model: model.header)

            VStack(alignment: .leading, spacing: ds.spacing.sm) {
                Text(model.emptyTitle)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)

                Text(model.emptyBody)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(ds.colors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ds.spacing.base)
            .padding(.vertical, ds.spacing.lg)
        }
    }
}

// MARK: - Model

extension IntegrationsDetailView {
    struct Model {
        let header: SettingsDetailHeader.Model
        let emptyTitle: String
        let emptyBody: String
    }
}
