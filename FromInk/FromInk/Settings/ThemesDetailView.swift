import SwiftUI

/// Themes detail — V1 stub. The theme system (custom paper / ink
/// palettes beyond Light / Dark) is future work. Header chrome
/// shared with the other detail screens via `SettingsDetailHeader`.
///
/// Component view: zero state, zero TCA.
///
struct ThemesDetailView: View {
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

extension ThemesDetailView {
    struct Model {
        let header: SettingsDetailHeader.Model
        let emptyTitle: String
        let emptyBody: String
    }
}
