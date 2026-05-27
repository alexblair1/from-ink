import SwiftUI

/// Branded toggle row: mono label leading, system Toggle trailing,
/// tinted with the ink token so it matches the rest of the chrome.
/// Used by the event creation form for the all-day toggle; also
/// reusable for any other boolean field in a branded form.
///
/// `isOn` is passed as a value plus an `onChange` closure rather than
/// a `Binding<Bool>` so the parent reducer is unambiguously the source
/// of truth — the view can't toggle local state without a corresponding
/// action being dispatched.
struct AllDayToggleRow: View {
    let model: Model

    var body: some View {
        HStack(spacing: model.innerSpacing) {
            MonoLabel(model.label, color: model.labelColor)
                .frame(width: model.labelColumnWidth, alignment: .leading)
            Spacer(minLength: 0)
            Toggle(
                "",
                isOn: Binding(
                    get: { model.isOn },
                    set: { model.onChange($0) }
                )
            )
            .labelsHidden()
            .tint(model.tint)
        }
        .padding(.horizontal, model.horizontalPadding)
        .frame(height: model.height)
    }
}

extension AllDayToggleRow {
    struct Model {
        let label: String
        let isOn: Bool
        let onChange: (Bool) -> Void
        let labelColor: Color
        let tint: Color
        let horizontalPadding: CGFloat
        let innerSpacing: CGFloat
        let labelColumnWidth: CGFloat
        let height: CGFloat
    }
}

extension AllDayToggleRow.Model {
    init(
        label: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void,
        labelColumnWidth: CGFloat = 88,
        ds: DesignSystem = .standard
    ) {
        self.label = label
        self.isOn = isOn
        self.onChange = onChange
        self.labelColor = ds.colors.ink3
        self.tint = ds.colors.ink
        self.horizontalPadding = ds.spacing.base
        self.innerSpacing = ds.spacing.md
        self.labelColumnWidth = labelColumnWidth
        self.height = ds.layout.hitTarget
    }
}
