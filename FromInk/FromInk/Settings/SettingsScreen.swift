import SwiftUI

/// Branded settings overlay — centered card on a dimmed backdrop.
/// Matches the NewNotebookOverlay style: sharp corners, hairline ink border, editorial typography.
///
struct SettingsScreen: View {
    let onDismiss: () -> Void

    @State private var destination: SettingsDestination?
    private let ds = DesignSystem.standard

    var body: some View {
        ZStack {
            // Scrim
            ds.colors.ink.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Card
            VStack(alignment: .leading, spacing: 0) {
                if let destination {
                    switch destination {
                    case .appearance:
                        AppearanceSettingsScreen(
                            onBack: {
                                withAnimation(ds.animation.standard) {
                                    self.destination = nil
                                }
                            },
                            onDismiss: onDismiss
                        )
                    }
                } else {
                    settingsList
                }
            }
            .frame(width: 380)
            .background(ds.colors.paper)
            .overlay(
                Rectangle().strokeBorder(ds.colors.ink, lineWidth: 1)
            )
        }
    }

    // MARK: - Settings list

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                MonoLabel(AppStrings.Settings.title, color: ds.colors.ink2)
                Spacer()
                IconButton("xmark", size: .footnote, color: ds.colors.ink2, action: onDismiss)
            }
            .padding(.horizontal, ds.spacing.base)
            .frame(height: ds.spacing.xxl)

            HairlineRule()

            // Rows
            settingsRow(
                icon: "circle.lefthalf.filled",
                title: AppStrings.Settings.appearance,
                action: {
                    withAnimation(ds.animation.standard) {
                        destination = .appearance
                    }
                }
            )

            HairlineRule()
        }
    }

    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: ds.spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ds.colors.ink)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ds.colors.ink3)
            }
            .padding(.horizontal, ds.spacing.base)
            .frame(height: ds.layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Destinations

enum SettingsDestination: Hashable {
    case appearance
}
