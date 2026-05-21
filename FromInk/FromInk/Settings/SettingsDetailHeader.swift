import SwiftUI

/// Shared header chrome for every settings detail screen — back
/// chevron + centered title + dismiss X + hairline rule.
///
/// Extracted from `OptionPickerDetailView` / `IntegrationsDetailView`
/// so spacing, fonts, hit targets, and the divider treatment live in
/// one place. The next detail screen added inherits the same chrome
/// by reusing this component.
///
/// Component view: zero state, zero TCA. The wiring view resolves
/// localized strings and tap callbacks via `Model`.
///
struct SettingsDetailHeader: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: model.onBack) {
                    HStack(spacing: ds.spacing.sm) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 12, weight: .medium))
                        MonoLabel(model.backLabel, color: ds.colors.ink2)
                    }
                    .foregroundStyle(ds.colors.ink2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                MonoLabel(model.title, color: ds.colors.ink2)

                Spacer()

                IconButton("xmark", size: .footnote, color: ds.colors.ink2, action: model.onDismiss)
            }
            .padding(.horizontal, ds.spacing.base)
            .frame(height: ds.spacing.xxl)

            HairlineRule()
        }
    }
}

// MARK: - Model

extension SettingsDetailHeader {
    struct Model {
        let title: String
        let backLabel: String
        let onBack: () -> Void
        let onDismiss: () -> Void
    }
}
