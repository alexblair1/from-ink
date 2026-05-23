import SwiftUI

/// A single connected-account row inside an integration provider
/// group. Left: account name (bold if default). Right: either the
/// account email + chevron (healthy), or a flag-red "Re-authenticate"
/// mono label + chevron (token expired).
///
/// Component view: zero state, zero TCA. Two callbacks — primary
/// row tap and the re-auth action — both injected via Model.
///
struct IntegrationAccountRow: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: primaryAction) {
            HStack(spacing: ds.spacing.sm) {
                Text(model.name)
                    .font(.system(size: 14, weight: model.isDefault ? .medium : .regular))
                    .foregroundStyle(ds.colors.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                trailing

                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(ds.colors.ink3)
            }
            .padding(.horizontal, ds.spacing.sm)
            .frame(minHeight: ds.layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.status {
        case .healthy:
            Text(model.email)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ds.colors.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
        case .reauthRequired:
            Text(model.reauthLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(ds.colors.flagRed)
                .lineLimit(1)
        }
    }

    /// Re-auth tap shortcut: if the row is in `.reauthRequired`,
    /// pressing it fires `onReauthTap` rather than the generic
    /// row tap. Single tap target = simpler hit map than a separate
    /// "Re-authenticate" button.
    private func primaryAction() {
        switch model.status {
        case .healthy:        model.onTap()
        case .reauthRequired: model.onReauthTap()
        }
    }
}

// MARK: - Model

extension IntegrationAccountRow {
    struct Model: Identifiable, Equatable {
        let id: UUID
        let name: String
        let email: String
        let isDefault: Bool
        let status: Status
        let reauthLabel: String
        let onTap: () -> Void
        let onReauthTap: () -> Void

        enum Status: Equatable {
            case healthy
            case reauthRequired
        }

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.id == rhs.id
                && lhs.name == rhs.name
                && lhs.email == rhs.email
                && lhs.isDefault == rhs.isDefault
                && lhs.status == rhs.status
        }
    }
}
