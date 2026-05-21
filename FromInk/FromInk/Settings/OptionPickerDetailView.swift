import SwiftUI

/// Generic single-select option picker — header + list of options +
/// checkmark on the active row. Powers both Appearance (Light / Dark
/// / System) and Handedness (Right / Left), and any future settings
/// of the same shape (units, timezone, font, etc.).
///
/// Component view: zero state, zero TCA. The `Value` type parameter
/// is whatever enum the setting uses. `Value: Hashable` is sufficient
/// to act as its own `Identifiable.id`.
///
/// Replaces the prior `AppearanceDetailView` and `HandednessDetailView`
/// files, which were 90% duplicate code.
///
struct OptionPickerDetailView<Value: Hashable>: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsDetailHeader(model: model.header)

            ForEach(model.options) { option in
                Button {
                    model.onSelect(option.value)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(ds.colors.ink)

                        Spacer()

                        if option.isSelected {
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

// MARK: - Model

extension OptionPickerDetailView {
    struct Model {
        let header: SettingsDetailHeader.Model
        let options: [Option]
        let onSelect: (Value) -> Void
    }

    /// `Value: Hashable` doubles as `Identifiable.id` — no separate
    /// id property needed since enum cases hash to distinct values.
    struct Option: Identifiable {
        let value: Value
        let label: String
        let isSelected: Bool
        var id: Value { value }
    }
}
