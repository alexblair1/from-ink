import SwiftUI

/// Appearance detail view inside the settings card.
/// Shown inline — not a separate sheet or navigation push.
///
struct AppearanceSettingsScreen: View {
    @AppStorage("appearanceSetting") private var appearance: AppearanceSetting = .system
    let onBack: () -> Void
    let onDismiss: () -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: ds.spacing.sm) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        MonoLabel(AppStrings.Settings.title, color: ds.colors.ink2)
                    }
                    .foregroundStyle(ds.colors.ink2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                MonoLabel(AppStrings.Settings.appearance, color: ds.colors.ink2)

                Spacer()

                IconButton("xmark", size: .footnote, color: ds.colors.ink2, action: onDismiss)
            }
            .padding(.horizontal, ds.spacing.base)
            .frame(height: ds.spacing.xxl)

            HairlineRule()

            // Options
            ForEach(AppearanceSetting.allCases, id: \.rawValue) { option in
                Button {
                    appearance = option
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(ds.colors.ink)

                        Spacer()

                        if appearance == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .medium))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(ds.colors.ink)
                        }
                    }
                    .padding(.horizontal, ds.spacing.base)
                    .frame(height: ds.layout.hitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HairlineRule()
            }
        }
    }
}
