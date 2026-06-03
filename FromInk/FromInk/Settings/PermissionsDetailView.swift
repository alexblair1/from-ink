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
/// Component view: zero TCA imports, zero DesignSystem access in
/// `body`. Every visual value is pre-resolved on the Model in its
/// init. Lifecycle wiring (`onAppear`, scene-active refresh) lives in
/// `SettingsView+Adapter` which forwards to `PermissionsFeature`.
struct PermissionsDetailView: View {
    let model: Model
    @Environment(\.scenePhase) private var scenePhase

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
            VStack(alignment: .leading, spacing: model.headerLineSpacing) {
                HStack(spacing: model.titleRowSpacing) {
                    Image(systemName: row.icon)
                        .font(model.iconFont)
                        .foregroundStyle(model.iconColor)
                        .frame(width: model.iconFrame)

                    Text(row.title)
                        .font(model.titleFont)
                        .foregroundStyle(model.titleColor)

                    Spacer()

                    // Status pill — same MonoLabel treatment as every
                    // other mono status pill in Settings. Keeps the
                    // typographic family tight.
                    MonoLabel(
                        row.statusLabel,
                        size: model.statusSize,
                        color: row.statusColor
                    )
                }

                // Body description — italics is kept here intentionally
                // (descriptive sentence, not a row title).
                Text(row.body)
                    .font(model.bodyFont)
                    .italic()
                    .foregroundStyle(model.bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, model.bodyIndent)

                // CTA hint — MonoLabel matches the affordance grammar
                // used by SettingsActionRow.
                MonoLabel(row.cta, size: model.ctaSize, color: model.ctaColor)
                    .padding(.leading, model.bodyIndent)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
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
        // Layout
        let headerLineSpacing: CGFloat
        let titleRowSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let iconFrame: CGFloat
        let bodyIndent: CGFloat
        // Typography
        let iconFont: Font
        let titleFont: Font
        let bodyFont: Font
        let statusSize: CGFloat
        let ctaSize: CGFloat
        // Colors
        let iconColor: Color
        let titleColor: Color
        let bodyColor: Color
        let ctaColor: Color
        // Lifecycle
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
