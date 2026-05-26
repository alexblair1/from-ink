import SwiftUI

/// Permissions detail — surfaces system-granted access (currently
/// Calendar and Reminders via EventKit) with a row per capability.
///
/// Row tap behavior:
/// - `.notDetermined` → triggers the iOS system prompt via the reducer.
/// - Any resolved state → opens the system Settings app deep link.
///
/// Header chrome shared with the other detail screens.
///
/// Component view: zero TCA imports. Lifecycle wiring (`onAppear`,
/// scene-active refresh) lives in `SettingsView+Adapter` which forwards
/// to `PermissionsFeature`.
struct PermissionsDetailView: View {
    let model: Model
    @Environment(\.scenePhase) private var scenePhase

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsDetailHeader(model: model.header)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.rows) { row in
                    permissionRow(row)
                    HairlineRule()
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear { model.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            // User likely flipped the toggle in the system Settings app
            // and returned — re-read statuses so labels stay live.
            guard phase == .active else { return }
            model.onSceneBecameActive()
        }
    }

    @ViewBuilder
    private func permissionRow(_ row: Row) -> some View {
        Button(action: row.onTap) {
            VStack(alignment: .leading, spacing: ds.spacing.xs) {
                HStack(spacing: ds.spacing.md) {
                    Image(systemName: row.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(ds.colors.ink2)
                        .frame(width: 24)

                    Text(row.title)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(ds.colors.ink)

                    Spacer()

                    Text(row.statusLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(row.statusColor)
                        .kerning(0.5)
                        .textCase(.uppercase)
                }

                Text(row.body)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(ds.colors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24 + ds.spacing.md)

                Text(row.cta)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(ds.colors.ink3)
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .padding(.leading, 24 + ds.spacing.md)
            }
            .padding(.horizontal, ds.spacing.base)
            .padding(.vertical, ds.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

extension PermissionsDetailView {
    struct Model {
        let header: SettingsDetailHeader.Model
        let rows: [Row]
        let onAppear: () -> Void
        let onSceneBecameActive: () -> Void
    }

    struct Row: Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
        let statusLabel: String
        let statusColor: Color
        let cta: String
        let onTap: () -> Void
    }
}

// MARK: - Status → label / color resolution

extension PermissionAuthStatus {
    var statusLabel: String {
        switch self {
        case .notDetermined: return AppStrings.Settings.permissionStatusNotDetermined
        case .denied:        return AppStrings.Settings.permissionStatusDenied
        case .restricted:    return AppStrings.Settings.permissionStatusRestricted
        case .writeOnly:     return AppStrings.Settings.permissionStatusWriteOnly
        case .fullAccess:    return AppStrings.Settings.permissionStatusFullAccess
        }
    }

    /// Mono status pill color. The design system uses the same `ink`
    /// scale for almost everything; the denied/restricted states get a
    /// flag color to draw attention.
    func statusColor(ds: DesignSystem = .standard) -> Color {
        switch self {
        case .notDetermined: return ds.colors.ink2
        case .denied, .restricted: return ds.colors.flagRed
        case .writeOnly: return ds.colors.ink2
        case .fullAccess: return ds.colors.ink
        }
    }

    var ctaLabel: String {
        switch self {
        case .notDetermined: return AppStrings.Settings.permissionCTAGrant
        default:             return AppStrings.Settings.permissionCTAManage
        }
    }
}
