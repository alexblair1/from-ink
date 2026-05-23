import SwiftUI

/// An in-flight add-account row. Renders inside the provider's group
/// while the OAuth handoff is running, and stays in place to surface
/// any of the four failure modes per the design (Cancelled,
/// Permissions denied, No connection, Couldn't verify).
///
/// Tap behavior depends on phase:
///   - `.connecting`: row is not tappable (user is mid-flow).
///   - `.failed(.userCancelled / .permissionsDenied / .network)`:
///     primary tap retries the auth flow.
///   - `.failed(.stateMismatch)`: NOT auto-retryable per the design;
///     primary tap dismisses the row (user must initiate a fresh
///     "+ Add account" tap).
///
/// Component view: zero state, zero TCA.
///
struct IntegrationPendingRow: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: model.onPrimaryTap) {
            HStack(spacing: ds.spacing.sm) {
                Text(model.title)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(ds.colors.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                statusLabel
            }
            .padding(.horizontal, ds.spacing.sm)
            .frame(minHeight: ds.layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
    }

    @ViewBuilder
    private var statusLabel: some View {
        Text(model.statusText)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(statusColor)
            .lineLimit(1)
    }

    private var statusColor: Color {
        switch model.statusKind {
        case .live:      ds.colors.ink
        case .neutral:   ds.colors.ink2
        case .attention: ds.colors.flagRed
        }
    }
}

// MARK: - Model

extension IntegrationPendingRow {
    struct Model: Identifiable, Equatable {
        let id: UUID
        let title: String
        let statusText: String
        let statusKind: StatusKind
        let accessibilityLabel: String
        let onPrimaryTap: () -> Void

        enum StatusKind: Equatable {
            /// In-flight; ink mono ("PKCE", "Verifying").
            case live
            /// Recoverable, non-attention ("Cancelled"). Ink-2 mono.
            case neutral
            /// Recoverable, needs eye ("No connection",
            /// "Permissions denied", "Couldn't verify"). Flag-red mono.
            case attention
        }

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.statusText == rhs.statusText
                && lhs.statusKind == rhs.statusKind
        }
    }
}
