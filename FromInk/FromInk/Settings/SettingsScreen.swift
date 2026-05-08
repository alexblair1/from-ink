import SwiftUI

struct SettingsScreen: View {
    @AppStorage("appearanceSetting") private var appearance: AppearanceSetting = .system
    let onDismiss: () -> Void

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                title: AppStrings.Settings.title,
                onDismiss: onDismiss
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Appearance section
                    SectionHeader(model: .init(title: AppStrings.Settings.appearance))
                        .padding(.horizontal, ds.spacing.lg)

                    VStack(spacing: 0) {
                        ForEach(AppearanceSetting.allCases, id: \.rawValue) { option in
                            Button {
                                appearance = option
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .font(ds.typography.body)
                                        .foregroundStyle(ds.colors.ink)

                                    Spacer()

                                    if appearance == option {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .medium))
                                            .symbolRenderingMode(.monochrome)
                                            .foregroundStyle(ds.colors.ink)
                                    }
                                }
                                .padding(.horizontal, ds.spacing.lg)
                                .frame(height: ds.layout.hitTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            HairlineRule()
                                .padding(.horizontal, ds.spacing.lg)
                        }
                    }
                }
            }
        }
        .background(ds.colors.paper)
    }
}

// MARK: - RawRepresentable conformance for @AppStorage

extension AppearanceSetting: RawRepresentable {}
