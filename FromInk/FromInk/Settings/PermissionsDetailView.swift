import SwiftUI

/// Permissions detail — V1 stub. Real implementation surfaces
/// EventKit Calendar / Reminders, Contacts, Notifications, etc.
/// permission states with a deep link into the system Settings app
/// to grant or revoke. That's a self-contained slice of its own
/// (permission status queries, system Settings deep-link, restricted
/// vs. denied vs. not-determined messaging).
///
/// Header chrome shared with the other detail screens.
///
/// Component view: zero state, zero TCA.
///
struct PermissionsDetailView: View {
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

extension PermissionsDetailView {
    struct Model {
        let header: SettingsDetailHeader.Model
        let emptyTitle: String
        let emptyBody: String
    }
}
